require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  Capybara.server_host = "127.0.0.1"
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # A freshly loaded page can be visible before its deferred Vite module has
  # installed Turbo's link/form handlers. Wait for the real JS runtime rather
  # than letting a fast click accidentally exercise a full-page fallback.
  def wait_for_turbo
    ready = Capybara.using_wait_time(5) do
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        const deadline = performance.now() + 4000;
        function check() {
          if (window.Turbo) return done(true);
          if (performance.now() >= deadline) return done(false);
          setTimeout(check, 25);
        }
        check();
      JS
    end
    assert ready, "Turbo failed to load: #{page.driver.browser.logs.get(:browser).map(&:message).join('\n')}"
  end
end
