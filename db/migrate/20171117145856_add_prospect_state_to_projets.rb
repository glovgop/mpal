class AddProspectStateToProjets < ActiveRecord::Migration[5.1]
  def change
    add_column :projets, :prospect_state, :string
  end
end
