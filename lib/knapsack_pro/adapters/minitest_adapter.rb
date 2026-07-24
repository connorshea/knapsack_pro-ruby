# frozen_string_literal: true

module KnapsackPro
  module Adapters
    class MinitestAdapter < BaseAdapter
      TEST_DIR_PATTERN = 'test/**{,/*/**}/*_test.rb'
      @@parent_of_test_dir = nil

      @parent_of_test_dir_regexp = nil
      @parent_of_test_dir_regexp_source = nil
      @const_source_locations = {}

      def self.test_path(obj)
        klass = obj.class
        path = const_source_location_for(klass)

        if path.nil? # Dynamically defined class (Minitest::Spec `describe "oneword"`)
          test_method_name = klass.runnable_methods.first
          path, _line = obj.method(test_method_name).source_location
        end

        path.gsub(parent_of_test_dir_regexp, '.')
      end

      module BindTimeTrackerMinitestPlugin
        def before_setup
          super
          KnapsackPro.tracker.current_test_path = KnapsackPro::Adapters::MinitestAdapter.test_path(self)
          KnapsackPro.tracker.start_timer
        end

        def after_teardown
          KnapsackPro.tracker.stop_timer
          super
        end
      end

      def bind_time_tracker
        ::Minitest::Test.send(:include, BindTimeTrackerMinitestPlugin)

        add_post_run_callback do
          KnapsackPro.logger.debug(KnapsackPro::Presenter.global_time)
        end
      end

      def bind_save_report
        add_post_run_callback do
          KnapsackPro::Report.save
        end
      end

      def set_test_helper_path(file_path)
        test_dir_path = File.dirname(file_path)
        @@parent_of_test_dir = File.expand_path('../', test_dir_path)
      end

      # `test_path` runs for every test, so do not recompile the regexp or
      # look up the source location of the same test class over and over.
      # The memo is keyed on the parent dir it was built from, so it
      # self-invalidates whenever `@@parent_of_test_dir` changes.
      def self.parent_of_test_dir_regexp
        if @parent_of_test_dir_regexp.nil? || @parent_of_test_dir_regexp_source != @@parent_of_test_dir
          @parent_of_test_dir_regexp_source = @@parent_of_test_dir
          @parent_of_test_dir_regexp = Regexp.new("^#{@@parent_of_test_dir}")
        end

        @parent_of_test_dir_regexp
      end

      def self.const_source_location_for(klass)
        return @const_source_locations[klass] if @const_source_locations.key?(klass)

        path, _line =
          begin
            Object.const_source_location(klass.to_s)
          rescue NameError # Dynamically defined class (Minitest::Spec `describe "more words"`)
            nil
          end

        @const_source_locations[klass] = path
      end

      module BindQueueModeMinitestPlugin
        def before_setup
          super

          unless ENV['KNAPSACK_PRO_BEFORE_QUEUE_HOOK_CALLED']
            KnapsackPro::Hooks::Queue.call_before_queue
            ENV['KNAPSACK_PRO_BEFORE_QUEUE_HOOK_CALLED'] = 'true'
          end

          KnapsackPro.tracker.current_test_path = KnapsackPro::Adapters::MinitestAdapter.test_path(self)
          KnapsackPro.tracker.start_timer
        end

        def after_teardown
          KnapsackPro.tracker.stop_timer

          super
        end
      end

      def bind_queue_mode
        ::Minitest::Test.send(:include, BindQueueModeMinitestPlugin)

        add_post_run_callback do
          KnapsackPro.logger.debug(KnapsackPro::Presenter.global_time)
        end
      end

      private

      def add_post_run_callback(&block)
        if ::Minitest.respond_to?(:after_run)
          ::Minitest.after_run { block.call }
        else
          ::Minitest::Unit.after_tests { block.call }
        end
      end
    end
  end
end
