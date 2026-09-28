# Run with: bundle exec ruby script/diagnostics/ruby_llm_batch_indices.rb
# No Rails, credentials, network, database, or Workbench workaround is loaded.
require "ruby_llm"

provider = Object.new
def provider.batch_status(*) = :succeeded
def provider.batch_results(*) = @rows

puts "RubyLLM #{Gem.loaded_specs.fetch('ruby_llm').version}"
{
  negative: [ [ 0, nil, :failed ], [ -1, nil, :cancelled ] ],
  duplicate: [ [ 0, nil, :failed ], [ 0, nil, :cancelled ] ],
  out_of_range: [ [ 2, nil, :failed ] ]
}.each do |name, rows|
  provider.instance_variable_set(:@rows, rows)
  batch = RubyLLM::Batch.new(provider:, id: "synthetic", raw_status: "completed", completed: true, request_count: 2)
  begin
    puts "#{name}: ACCEPTED slots=#{batch.messages.size} statuses=#{batch.statuses.inspect}"
  rescue RubyLLM::Error => error
    puts "#{name}: REJECTED #{error.class}"
  end
end
