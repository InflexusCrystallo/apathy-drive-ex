defmodule ApathyDrive.Scripts.MeltInv do
  alias ApathyDrive.{Character, Item, ItemInstance, Mobile, Repo, Room}

  def execute(%Room{} = room, _mobile_ref, target_ref) do
    Room.update_mobile(room, target_ref, fn
      %Character{} = character ->
        Enum.each(character.inventory, fn item ->
          Mobile.send_scroll(
            character,
            "<p>#{Item.colored_name(item, character: character)} <span class='red'>melts away!</span></p>"
          )

          ItemInstance
          |> Repo.get(item.instance_id)
          |> Repo.delete!()
        end)

        Character.load_items(character)

      _ ->
        room
    end)
  end
end
