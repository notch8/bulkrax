require 'rails_helper'

module Bulkrax
  RSpec.describe ImporterJob, type: :job do
    let(:importer) { FactoryBot.create(:bulkrax_importer_oai) }

    before(:each) do
      allow(Bulkrax::Importer).to receive(:find).with(1).and_return(importer)
    end

    describe 'successful job' do
      it 'calls import_works with false' do
        expect(importer).to receive(:import_works).with(false)
        subject.perform(1)
      end

      it 'calls import_works with true if only_updates_since_last_import=true' do
        expect(importer).to receive(:import_works).with(true)
        subject.perform(1, true)
      end
    end

    describe 'unsuccessful job' do
      let(:importer) { FactoryBot.create(:bulkrax_importer_csv_bad) }

      it 'raises an error with an invalid import' do
        expect { subject.perform(1) }.to raise_error(RuntimeError, 'Missing required elements, required elements are: title, source_identifier')
      end
    end

    describe 'schedulable' do
      before do
        allow(importer).to receive(:schedulable?).and_return(true)
        allow(importer).to receive(:next_import_at).and_return(1)
      end

      it 'schedules import_works when schedulable?' do
        expect(importer).to receive(:import_works).with(false)
        expect(ImporterJob).to receive(:set).with(wait_until: 1).and_return(ImporterJob)
        subject.perform(1)
      end
    end
  end
end
