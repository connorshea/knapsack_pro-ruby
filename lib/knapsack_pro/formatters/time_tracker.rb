# frozen_string_literal: true

require 'stringio'
require 'set'
require_relative '../utils'

module KnapsackPro
  module Formatters
    class TimeTracker
      # The subset of an RSpec example needed by `#current_batch_failed_paths`.
      # Keeping only these values avoids recomputing the file path for every
      # example once per batch, and avoids holding on to the example objects.
      RecordedExample = Struct.new(:file_path, :id, :status)

      ::RSpec::Core::Formatters.register self,
        :example_group_started,
        :example_started,
        :example_finished,
        :example_group_finished

      attr_reader :output # RSpec < v3.10.2

      def initialize(_output)
        @output = StringIO.new
        @time_each = nil
        @time_all = nil
        @time_all_by_group_id_path = Hash.new(0)
        @group = {}
        @paths = {}
        @suite_started = now
        @batched_scheduled_paths = []
        @split_by_test_example_file_paths = Set.new
        @current_batch_examples = []
        @group_id_paths = {}
      end

      def current_batch_failed_paths
        examples_by_file_path = @current_batch_examples
          .group_by(&:file_path)

        paths =
          examples_by_file_path.flat_map do |file_path, examples|
            failed_id_paths = examples.filter { |example| example.status == :failed }.map(&:id)
            next [] if failed_id_paths.none?
            next file_path if KnapsackPro::Config::Env.test_files_encrypted?
            # Other nodes may have run some examples from this file, it's not safe to compact.
            next failed_id_paths if rspec_split_by_test_example?(file_path)
            next file_path if failed_id_paths.size == examples.size

            failed_id_paths
          end

        paths.map { |path| KnapsackPro::TestFileCleaner.clean(path) }
      end

      def schedule(paths)
        @current_batch_examples = []
        @batched_scheduled_paths << paths

        paths.each do |path|
          next unless KnapsackPro::Adapters::RSpecAdapter.id_path?(path)

          file_path = KnapsackPro::Adapters::RSpecAdapter.parse_file_path(path)
          @split_by_test_example_file_paths << KnapsackPro::TestFileCleaner.clean(file_path)
        end
      end

      def example_group_started(notification)
        record_time_all(notification.group.parent_groups[1], @time_all_by_group_id_path, @time_all)
        @time_all = now
      end

      def example_started(notification)
        record_time_all(notification.example.example_group, @time_all_by_group_id_path, @time_all)
        @time_each = now
      end

      def example_finished(notification)
        record_example(@group, notification.example, @time_each)
        @time_all = now
      end

      def example_group_finished(notification)
        record_time_all(notification.group, @time_all_by_group_id_path, @time_all)
        @time_all = now
        return unless top_level_group?(notification.group)

        add_hooks_time(@group, @time_all_by_group_id_path)
        @time_all_by_group_id_path = Hash.new(0)
        merge_into(@paths, @group)
        @group = {}
        # The groups of a finished test file are never asked for their id path
        # again, so keep the cache scoped to a single test file.
        @group_id_paths.clear
      end

      def queue
        recorded_paths = @paths.values.map do |example|
          KnapsackPro::Adapters::RSpecAdapter.parse_file_path(example[:path])
        end

        missing = (@batched_scheduled_paths.flatten - recorded_paths).each_with_object({}) do |path, object|
          object[path] = { path: path, time_execution: 0.0 }
        end

        merge(@paths, missing).values.map do |example|
          example.transform_keys(&:to_s)
        end
      end

      def batch
        @paths.values.map do |example|
          example.transform_keys(&:to_s)
        end
      end

      def duration
        now - @suite_started
      end

      def unexecuted_test_paths
        pending_paths = @paths.values
          .filter { |example| example[:time_execution] == 0.0 }
          .map { |example| example[:path] }

        not_run_paths = @batched_scheduled_paths.flatten -
          @paths.values
          .map { |example| example[:path] }

        pending_paths + not_run_paths
      end

      private

      def top_level_group?(group)
        group.metadata[:parent_example_group].nil?
      end

      def add_hooks_time(group, time_all_by_group_id_path)
        return if time_all_by_group_id_path.empty?

        # `group_id_path` without its trailing `]` is compared against every
        # example of the group, so build it once per group instead of per pair.
        hooks_time = time_all_by_group_id_path.map do |group_id_path, time|
          [group_id_path, group_id_path[0..-2], time]
        end

        group.each_value do |example|
          next if example[:time_execution] == 0.0

          path = example[:path]
          sum = 0.0
          hooks_time.each do |group_id_path, group_id_path_prefix, time|
            # :path is a file path (a_spec.rb), sum any before/after(:all) in the file
            # :path is an id path (a_spec.rb[1:1]), sum any before/after(:all) above it
            if group_id_path.start_with?(path) || path.start_with?(group_id_path_prefix)
              sum += time
            end
          end

          example[:time_execution] += sum
        end
      end

      def record_example(accumulator, example, started_at)
        file_path = file_path_for(example)
        return if file_path == ""

        status = example.execution_result.status
        path =
          if rspec_split_by_test_example?(file_path)
            KnapsackPro::TestFileCleaner.clean(example.id)
          else
            file_path
          end

        @current_batch_examples << RecordedExample.new(file_path, example.id, status)

        time_execution = status == :pending ? 0.0 : (now - started_at).to_f
        recorded = accumulator[path]
        if recorded
          recorded[:time_execution] += time_execution
        else
          accumulator[path] = { path: path, time_execution: time_execution }
        end
      end

      def record_time_all(group, time_all_by_group_id_path, time_all)
        return unless group # above top level group

        # `RSpec::Core::ExampleGroup.id` is not memoized and this runs for every
        # example, so cache the cleaned id path per group for the current batch.
        group_id_path = @group_id_paths[group] ||= KnapsackPro::TestFileCleaner.clean(group.id)
        time_all_by_group_id_path[group_id_path] += now - time_all
      end

      def rspec_split_by_test_example?(file_path)
        @split_by_test_example_file_paths.include?(file_path)
      end

      def file_path_for(example)
        KnapsackPro::TestFileCleaner.clean(KnapsackPro::Adapters::RSpecAdapter.file_path_for(example))
      end

      def merge(h1, h2)
        h1.merge(h2) do |key, v1, v2|
          {
            path: key,
            time_execution: v1[:time_execution] + v2[:time_execution]
          }
        end
      end

      # `merge` rebuilds the whole accumulator, which is quadratic when called
      # once per top level group, so accumulate in place instead.
      def merge_into(accumulator, other)
        other.each do |path, example|
          recorded = accumulator[path]
          if recorded
            recorded[:time_execution] += example[:time_execution]
          else
            accumulator[path] = example
          end
        end
      end

      def now
        KnapsackPro::Utils.time_now
      end
    end
  end
end
