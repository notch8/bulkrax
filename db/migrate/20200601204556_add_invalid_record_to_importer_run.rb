class AddInvalidRecordToImporterRun < ActiveRecord::Migration[5.1]
  def change
    add_column :bulkrax_importer_runs, :invalid_records, :text unless column_exists?(:bulkrax_importer_runs, :invalid_records)
  end
end
