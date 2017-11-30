require 'simplecov'
SimpleCov.start if ENV['CODECOV_TOKEN'].present?

require 'codecov'
SimpleCov.formatter = SimpleCov::Formatter::Codecov
