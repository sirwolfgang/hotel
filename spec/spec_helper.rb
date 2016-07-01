require 'dotenv'
Dotenv.load

require 'simplecov'
require 'codeclimate-test-reporter'

SimpleCov.formatter =
  SimpleCov::Formatter::MultiFormatter.new([
                                             SimpleCov::Formatter::HTMLFormatter,
                                             CodeClimate::TestReporter::Formatter
                                           ])
SimpleCov.start do
  add_filter '/spec/'
end

require 'rails'
require 'jwt_keeper'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!

  config.default_formatter = 'doc' if config.files_to_run.one?

  # config.profile_examples = 10

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random
  Kernel.srand config.seed
end

RSpec.shared_context 'initialize config' do
  let(:config) do
    {
      algorithm:        'HS256',
      secret:           'secret',
      expiry:           24.hours,
      issuer:           'api.example.com',
      audience:         'example.com',
      redis_connection: Redis.new(url: ENV['REDIS_URL']),
      version:          nil,
      cookie_lock:      false
    }
  end

  before(:each) do
    JWTKeeper.configure(JWTKeeper::Configuration.new(config))
  end
end
