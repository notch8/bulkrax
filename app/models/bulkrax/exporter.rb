# frozen_string_literal: true
module Bulkrax
  class Exporter < ApplicationRecord
    include Bulkrax::ImporterExporterBehavior
    include Bulkrax::Status

    serialize :field_mapping, JSON
    serialize :last_error, JSON

    belongs_to :user
    has_many :exporter_runs, dependent: :destroy, foreign_key: 'exporter_id'
    has_many :entries, as: :importerexporter, dependent: :destroy

    validates :name, presence: true
    validates :parser_klass, presence: true

    delegate :write, :create_from_collection, :create_from_importer, :create_from_worktype, to: :parser

    def export
      current_exporter_run && setup_export_path
      case self.export_from
      when 'collection'
        create_from_collection
      when 'importer'
        create_from_importer
      when 'worktype'
        create_from_worktype
      end
      status_info
    rescue StandardError => e
      status_info(e)
    end

    def status
      if self.last_error_at.present?
        'Failed'
      elsif exporter_runs.last&.exporter_status
        exporter_runs.last&.exporter_status
      else
        'Pending'
      end
    end

    # #export_source accessors
    # Used in form to prevent it from getting confused as to which value to populate #export_source with.
    # Also, used to display the correct selected value when rendering edit form.
    def export_source_importer
      self.export_source if self.export_from == 'importer'
    end

    def export_source_collection
      self.export_source if self.export_from == 'collection'
    end

    def export_source_worktype
      self.export_source if self.export_from == 'worktype'
    end

    # If field_mapping is empty, setup a default based on the export_properties
    def mapping
      @mapping ||= self.field_mapping ||
                   ActiveSupport::HashWithIndifferentAccess.new(
                     export_properties.map do |m|
                       Bulkrax.default_field_mapping.call(m)
                     end.inject(:merge)
                   ) ||
                   [{}]
    end

    def export_from_list
      [
        [I18n.t('bulkrax.exporter.labels.importer'), 'importer'],
        [I18n.t('bulkrax.exporter.labels.collection'), 'collection'],
        [I18n.t('bulkrax.exporter.labels.worktype'), 'worktype']
      ]
    end

    def export_type_list
      [
        [I18n.t('bulkrax.exporter.labels.metadata'), 'metadata'],
        [I18n.t('bulkrax.exporter.labels.full'), 'full']
      ]
    end

    def importers_list
      Importer.all.map { |i| [i.name, i.id] }
    end

    def current_exporter_run
      @current_exporter_run ||= self.exporter_runs.create!(total_work_entries: self.limit || parser.total)
    end

    def setup_export_path
      FileUtils.mkdir_p(exporter_export_path) unless File.exist?(exporter_export_path)
    end

    def exporter_export_path
      @exporter_export_path ||= File.join(Bulkrax.export_path, self.id.to_s, self.exporter_runs.last.id.to_s)
    end

    def exporter_export_zip_path
      @exporter_export_zip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "export_#{self.id}_#{self.exporter_runs.last.id}.zip")
    rescue
      @exporter_export_zip_path ||= File.join(ENV.fetch('RAILS_TMP', Dir.tmpdir).to_s, "export_#{self.id}_0.zip")
    end

    def export_properties
      properties = Hyrax.config.registered_curation_concern_types.map { |work| work.constantize.properties.keys }.flatten.uniq.sort
      properties.reject { |prop| Bulkrax.reserved_properties.include?(prop) }
    end
  end
end
