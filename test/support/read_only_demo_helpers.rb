module ReadOnlyDemoHelpers
  def with_demo_mode(&block)
    with_replaced_method(Workbench::DemoMode, :enabled?, -> { true }, &block)
  end

  def with_replaced_method(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name, replacement)
    yield
  ensure
    target.define_singleton_method(name, original)
  end
end
