class CreateChatRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_rooms do |t|
      t.references :challenge, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
    add_index :chat_rooms, :challenge_id, unique: true
  end
end