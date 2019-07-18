require 'csv'

module Bulkrax
  class CsvEntry < Entry
    include Bulkrax::Concerns::HasMatchers

    serialize :raw_metadata, JSON

    matcher 'contributor', split: true
    matcher 'creator', split: true
    matcher 'date', split: true
    matcher 'description'
    matcher 'format_digital', parsed: true
    matcher 'format_original', parsed: true
    matcher 'identifier'
    matcher 'language', parsed: true, split: true
    matcher 'place'
    matcher 'publisher', split: true
    matcher 'rights_statement'
    matcher 'subject', split: true
    matcher 'title'
    matcher 'alternative_title'
    matcher 'types', from: %w[types type], split: true, parsed: true
    matcher 'file', split: true

    def build_metadata
      self.parsed_metadata = {}

      if record.nil?
        raise StandardError, 'Record not found'
      elsif required_elements?(record.keys) == false
        raise StandardError, "Missing required elements, required elements are: #{required_elements.join(', ')}"
      end

      record.each do |key, value|
        add_metadata(key, value)
      end
      add_visibility
      add_rights_statement
      add_collections
      self.parsed_metadata[Bulkrax.system_identifier_field] ||= [record['source_identifier']]

      self.parsed_metadata
    end

    def record
      @record ||= raw_metadata
    end

    def matcher_class
      Bulkrax::CsvMatcher
    end

    def collections_created?
      return true if record['collection'].blank?
      record['collection'].split(/\s*[:;|]\s*/).length == self.collection_ids.length
    end

    def find_or_create_collection_ids
      return self.collection_ids if collections_created?
      record['collection'].split(/\s*[:;|]\s*/).each do | collection |
        c = Collection.where(Bulkrax.system_identifier_field => collection).first
        self.collection_ids << c.id unless c.blank? || self.collection_ids.include?(c.id)
      end unless record['collection'].blank?
      return self.collection_ids
    end

    def required_elements?(keys)
      !required_elements.map { |el| keys.include?(el) }.include?(false)
    end

    def required_elements
      %w[title source_identifier]
    end
  end
end
