require "pathname"

module Learning
  class SourceReader
    SourceLine = Data.define(:number, :text)
    Snippet = Data.define(:reference, :lines)

    class Error < StandardError; end

    ALLOWED_ROOTS = %w[app config db docs lib test].freeze
    MAX_LINES = 80

    def self.read(reference, root: Rails.root)
      new(reference, root:).read
    end

    def initialize(reference, root: Rails.root)
      @reference = reference
      @root = Pathname.new(root.to_s).expand_path
    end

    def read
      path = safe_path
      lines = File.readlines(path, chomp: true)
      start_line, end_line = validated_range(lines.length)
      selected = lines[(start_line - 1), end_line - start_line + 1]

      unless selected&.length == end_line - start_line + 1
        raise Error, "Source range is outside #{ @reference.path }"
      end

      unless selected.join("\n").include?(@reference.anchor.to_s)
        raise Error, "Source anchor drifted in #{ @reference.path }: #{@reference.anchor}"
      end

      Snippet.new(
        reference: @reference,
        lines: selected.each_with_index.map { |text, index| SourceLine.new(number: start_line + index, text:) }.freeze
      )
    rescue Error
      raise
    rescue Errno::ENOENT, Errno::EACCES => error
      raise Error, "Unable to read learning source #{@reference.path}: #{error.message}"
    end

    private

    def safe_path
      relative_path = @reference.path.to_s
      first_component = relative_path.split("/", 2).first
      root_prefix = "#{@root}/"

      if relative_path.blank? || relative_path.start_with?("/") || relative_path.include?("\0") || !ALLOWED_ROOTS.include?(first_component)
        raise Error, "Learning source path is not allowlisted: #{relative_path.inspect}"
      end

      candidate = @root.join(relative_path).cleanpath
      unless candidate.to_s.start_with?(root_prefix)
        raise Error, "Learning source path escapes the repository: #{relative_path.inspect}"
      end

      real_path = candidate.realpath
      unless real_path.to_s.start_with?(root_prefix)
        raise Error, "Learning source symlink escapes the repository: #{relative_path.inspect}"
      end

      real_path
    end

    def validated_range(line_count)
      start_line = Integer(@reference.start_line)
      end_line = Integer(@reference.end_line)

      if start_line < 1 || end_line < start_line || end_line - start_line + 1 > MAX_LINES || end_line > line_count
        raise Error, "Invalid learning source range for #{@reference.path}: #{start_line}-#{end_line}"
      end

      [ start_line, end_line ]
    rescue ArgumentError, TypeError
      raise Error, "Learning source range is not numeric for #{@reference.path}"
    end
  end
end
