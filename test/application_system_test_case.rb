require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  Capybara.server_host = "127.0.0.1"
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
end
