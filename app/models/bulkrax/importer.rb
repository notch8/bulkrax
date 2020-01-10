# frozen_string_literal: true

require 'iso8601'

module Bulkrax
  class Importer < ApplicationRecord
    include Bulkrax::ImporterExporterBehavior

    serialize :parser_fields, JSON
    serialize :field_mapping, JSON

    belongs_to :user
    has_many :importer_runs, dependent: :destroy, foreign_key: 'importer_id'
    has_many :entries, as: :importerexporter, dependent: :destroy

    validates :name, presence: true
    validates :admin_set_id, presence: true
    validates :parser_klass, presence: true

    delegate :valid_import?, :create_parent_child_relationships, :write_errored_entries_file, to: :parser

    attr_accessor :only_updates, :file_style, :file
    # TODO: validates :metadata_prefix, presence: true
    # TODO validates :base_url, presence: true

    def mapping
      self.field_mapping = parser.import_fields.reject(&:nil?).map { |m| Bulkrax.default_field_mapping.call(m) }.inject(:merge) if self.field_mapping.blank? || self.field_mapping == [{}]
      @mapping ||= self.field_mapping
    end

    def parser_fields
      self[:parser_fields] || {}
    end

    def frequency_enums
      # these duration values use ISO 8601 Durations (https://en.wikipedia.org/wiki/ISO_8601#Durations)
      # TLDR; all durations are prefixed with 'P' and the parts are a number with the type of duration.
      # i.e. P1Y2M3W4DT5H6M7S == 1 Year, 2 Months, 3 Weeks, 4 Days, 5 Hours, 6 Minutes, 7 Seconds
      [['Daily', 'P1D'], ['Monthly', 'P1M'], ['Yearly', 'P1Y'], ['Once (on save)', 'PT0S']]
    end

    def frequency=(frequency)
      self[:frequency] = ISO8601::Duration.new(frequency).to_s
    end

    def frequency
      f = self[:frequency] || "PT0S"
      ISO8601::Duration.new(f)
    end

    def schedulable?
      frequency.to_seconds != 0
    end

    def current_importer_run
      @current_importer_run ||= self.importer_runs.create!(total_work_entries: self.limit || parser.total, total_collection_entries: parser.collections_total)
    end

    def seen
      @seen ||= {}
    end

    def replace_files
      self.parser_fields['replace_files']
    end

    def import_works(only_updates = false)
      self.only_updates = only_updates
      parser.create_works
      remove_unseen
    end

    def import_collections
      parser.create_collections
    end

    # Prepend the base_url to ensure unique set identifiers
    # @todo - move to parser, as this is OAI specific
    def unique_collection_identifier(id)
      "#{self.parser_fields['base_url'].split('/')[2]}_#{id}"
    end

    def remove_unseen
      # TODO
      # if primary_collection
      #   primary_collection.member_ids.each do |id|
      #     w = Work.find id
      #     unless seen[w.source[0]]
      #       if w.in_collections.size > 1
      #         primary_collection.members.delete w # only removes from primary collection - wants the record, not the id
      #         primary_collection.save
      #       else
      #         w.delete # removes from all collections
      #       end
      #     end
      #   end
      # end
    end

    # The format for metadata for the incoming import; corresponds to an Entry class
    def import_metadata_format
      [['CSV', 'Bulkrax::CsvEntry'], ['RDF (N-Triples)', 'Bulkrax::RdfEntry']]
    end

    # The type of metadata for the incoming import, either one file for all works, or one file per work
    # def import_metadata_type
    #   [['Single Metadata File for all works', 'single'], ['Multiple Files, one per Work', 'multi']]
    # end

    # If the import data is zipped, unzip it to this path
    def importer_unzip_path
      @importer_unzip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "import_#{self.id}_#{self.importer_runs.last.id}")
    rescue
      @importer_unzip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "import_#{self.id}_0")
    end

    def errored_entries_file_path
      @errored_entries_file_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "import_#{self.id}_errored_entries")
    end
  end
end
