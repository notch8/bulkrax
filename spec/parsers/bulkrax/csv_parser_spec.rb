# frozen_string_literal: true

require 'rails_helper'

module Bulkrax
  RSpec.describe CsvParser do
    describe '#create_works' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv) }
      let(:entry) { FactoryBot.create(:bulkrax_entry, importerexporter: importer) }
      subject { described_class.new(importer) }

      before(:each) do
        allow(Bulkrax::CsvEntry).to receive_message_chain(:where, :first_or_create!).and_return(entry)
        allow(entry).to receive(:id)
        allow(Bulkrax::ImportWorkJob).to receive(:perform_later)
      end

      context 'with malformed CSV' do
        before(:each) do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/malformed.csv' }
        end

        it 'returns an empty array, and records the error on the importer' do
          subject.create_works
          expect(importer.errors.details[:base].first[:error]).to eq('CSV::MalformedCSVError'.to_sym)
        end
      end

      context 'without an identifier column' do
        before(:each) do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/bad.csv' }
        end

        it 'skips all of the lines' do
          expect(subject.importerexporter).not_to receive(:increment_counters)
          subject.create_works
        end
      end

      context 'with a nil value in the identifier column' do
        before(:each) do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/ok.csv' }
        end

        it 'skips the bad line' do
          expect(subject).to receive(:increment_counters).once
          subject.create_works
        end
      end

      context 'with good data' do
        before(:each) do
          importer.parser_fields = { import_file_path: './spec/fixtures/csv/good.csv' }
        end

        it 'processes the line' do
          expect(subject).to receive(:increment_counters).twice
          subject.create_works
        end

        it 'counts the correct number of works and collections' do
          expect(subject.total).to eq(2)
          expect(subject.collections_total).to eq(2)
        end
      end
    end

    describe '#create_parent_child_relationships' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_complex) }
      let(:entry_1) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '123456789') }
      let(:entry_2) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '234567891') }
      let(:entry_3) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '345678912') }
      let(:entry_4) { FactoryBot.build(:bulkrax_entry, importerexporter: importer, identifier: '456789123') }
      subject { described_class.new(importer) }

      before do
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '123456789', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_1])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '234567891', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_2])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '345678912', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_3])
        allow(Bulkrax::CsvEntry).to receive(:where).with(identifier: '456789123', importerexporter_id: importer.id, importerexporter_type: 'Bulkrax::Importer').and_return([entry_4])
      end

      it 'sets up the list of parents and children' do
        expect(subject.parents).to eq("123456789" => ["234567891"], "234567891" => ["345678912"], "345678912" => ["456789123"], "456789123" => ["234567891"])
      end

      it 'invokes Bulkrax::ChildRelationshipsJob' do
        expect(Bulkrax::ChildRelationshipsJob).to receive(:perform_later).exactly(4).times
        subject.create_parent_child_relationships
      end
    end

    describe '#write_errored_entries_file', clean_downloads: true do
      subject                { described_class.new(importer) }
      let(:importer)         { FactoryBot.create(:bulkrax_importer_csv_failed, entries: [entry_failed, entry_succeeded, entry_collection]) }
      let(:entry_failed)     { FactoryBot.create(:bulkrax_csv_entry_failed, raw_metadata: { title: 'Failed' }) }
      let(:entry_succeeded)  { FactoryBot.create(:bulkrax_csv_entry, raw_metadata: { title: 'Succeeded' }) }
      let(:entry_collection) { FactoryBot.create(:bulkrax_csv_entry_collection, raw_metadata: { title: 'Collection' }, last_error: 'failed') }
      let(:import_file_path) { importer.errored_entries_csv_path }

      it 'returns true' do
        expect(subject.write_errored_entries_file).to eq(true)
      end

      it 'writes a CSV file to the correct location' do
        expect(File.exist?(import_file_path)).to eq(false)

        subject.write_errored_entries_file

        expect(File.exist?(import_file_path)).to eq(true)
      end

      it 'contains the contents of failed entries' do
        subject.write_errored_entries_file
        file_contents = File.read(import_file_path)

        expect(file_contents).to include('Failed,')
        expect(file_contents).to_not include('Succeeded')
      end

      it 'ignores failed collection entries' do
        subject.write_errored_entries_file
        file_contents = File.read(import_file_path)

        expect(file_contents).to_not include('Collection')
      end
    end
  end
end
