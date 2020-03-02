# frozen_string_literal: true

require 'nokogiri'
module Bulkrax
  # Generic XML Entry
  class XmlEntry < Entry
    serialize :raw_metadata, JSON

    def self.fields_from_data(data); end

    def self.read_data(path)
      # This doesn't cope with BOM sequences:
      # Nokogiri::XML(open(path), nil, 'UTF-8').remove_namespaces!
      Nokogiri::XML(open(path)).remove_namespaces!
    end

    def self.data_for_entry(data, path = nil)
      collections = []
      children = []
      xpath_for_source_id = ".//*[name()='#{source_identifier_field}']"
      return {
        source_identifier: data.xpath(xpath_for_source_id).first.text,
        # Remove tabs and and newlines
        data:
          data.to_xml(
            encoding: 'UTF-8',
            save_with:
              Nokogiri::XML::Node::SaveOptions::NO_DECLARATION | Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS
          ).gsub("\n", '').gsub("\t", ''),
        collection: collections,
        file: record_file_paths(path),
        children: children
      }
    end

    # Return all files in this directory and sub-directories, excluding the metadata file
    # Importing files is only supported on individual_file
    # Files must be the same, or a subdirectory of, that containing the xml
    def self.record_file_paths(path)
      return [] if path.nil?
      Dir.glob("#{File.dirname(path)}/**/*").reject { |f| File.file?(f) == false || f == path }
    end

    # def self.matcher_class; end

    def record
      @record ||= Nokogiri::XML(self.raw_metadata['data'], nil, 'UTF-8')
    end

    def build_metadata
      raise StandardError, 'Record not found' if record.nil?
      raise StandardError, 'Missing source identifier' if self.raw_metadata['source_identifier'].blank?
      self.parsed_metadata = {}
      self.parsed_metadata[Bulkrax.system_identifier_field] = [self.raw_metadata['source_identifier']]
      xml_elements.each do |element_name|
        elements = record.xpath("//*[name()='#{element_name}']")
        next if elements.blank?
        elements.each do |el|
          el.children.map { |node| node.content }.each do |content|
            add_metadata(element_name, content)
          end
        end
      end
      add_visibility
      add_rights_statement
      add_collections
      self.parsed_metadata['file'] = self.raw_metadata['file']

      add_local
      self.parsed_metadata
    end

    # Grab the class from the real parser
    def xml_elements
      Bulkrax.field_mappings[self.importerexporter.parser_klass].map do |_k, v|
        v[:from]
      end.flatten.compact.uniq
    end
  end
end
