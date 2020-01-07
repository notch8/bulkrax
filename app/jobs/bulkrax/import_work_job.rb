# frozen_string_literal: true

module Bulkrax
  class ImportWorkJob < ApplicationJob
    queue_as :import

    def perform(*args)
      entry = Entry.find(args[0])
      build_result = entry.build
      if build_result.present?
        entry.save!
        ImporterRun.find(args[1]).increment!(:processed_records)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
      else
        # do not retry here because whatever parse error kept you from creating a work will likely
        # keep preventing you from doing so.
        entry.save!
        ImporterRun.find(args[1]).increment!(:failed_records)
        ImporterRun.find(args[1]).decrement!(:enqueued_records)
      end
      entry.save!
    rescue Bulkrax::CollectionsCreatedError
      reschedule(args[0], args[1])
      # Exceptions here are not an issue with building the work.
      # Those are caught separately, these are more likely network, db or other unexpected issues.
      # Note that these temporary type issues do not raise the failure count
    rescue StandardError, OAIError, RSolr::Error::Http => e
      raise e
    end

    def reschedule(entry_id, run_id)
      ImportWorkJob.set(wait: 1.minute).perform_later(entry_id, run_id)
    end
  end
end
