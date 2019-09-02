defmodule ApathyDrive.Scripts.Cleave do
  alias ApathyDrive.{Ability, Mobile, Room}

  def execute(%Room{} = room, mobile_ref) do
    Room.update_mobile(room, mobile_ref, fn character ->
      targets = Ability.get_targets(room, mobile_ref, %Ability{targets: "full attack area"}, "")

      min_targets = min(2, length(targets))
      max_targets = length(targets)
      count = Enum.random(min_targets..max_targets)

      targets = Enum.take_random(targets, count)

      attack = Mobile.attack_ability(character)

      if attack.energy > div(character.max_energy, 2) do
        Mobile.send_scroll(
          character,
          "<p><span class='cyan'>You are not proficient enough with your equipped weapon to cleave.</span></p>"
        )

        character
      else
        if character.energy < attack.energy * 2 do
          if character.casting do
            Mobile.send_scroll(
              character,
              "<p><span class='dark-red'>You interrupt your other ability.</span></p>"
            )
          end

          Mobile.send_scroll(
            character,
            "<p><span class='cyan'>You move into position...</span></p>"
          )

          ability =
            "cleave"
            |> Ability.find()
            |> Map.put(:target_list, "")
            |> Map.put(:reaction_energy, attack.energy * 2)

          Map.put(character, :casting, ability)
        else
          character = Map.put(character, :energy, character.energy - attack.energy * 2)

          attack =
            attack
            |> Map.put(:energy, 0)
            |> Map.put(:ignores_round_cooldown?, true)

          room = put_in(room.mobiles[character.ref], character)

          Room.update_energy_bar(room, character.ref)

          Mobile.send_scroll(
            character,
            "<p><span class='red'>You swing your weapon in a wide arc...</span></p>"
          )

          Ability.execute(room, mobile_ref, attack, targets)
        end
      end
    end)
  end
end
