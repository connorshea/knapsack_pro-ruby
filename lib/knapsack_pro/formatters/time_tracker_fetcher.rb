# frozen_string_literal: true

module KnapsackPro
  module Formatters
    class TimeTrackerFetcher
      FORMATTER_NAME = "KnapsackPro::Formatters::TimeTracker"

      def self.call
        ::RSpec
          .configuration
          .formatters
          # `Class#name` is cached by Ruby, unlike `Class#to_s`.
          .find { |f| f.class.name == FORMATTER_NAME }
      end

      def self.unexecuted_test_paths
        time_tracker = call
        return [] unless time_tracker
        time_tracker.unexecuted_test_paths
      end
    end
  end
end
