defmodule ApathyDrive.Scripts.LesserElementalStrike do
  alias ApathyDrive.Room

  def execute(%Room{} = room, mobile_ref, target_ref) do
    Enum.reduce(1..4, room, fn _n, room ->
      ApathyDrive.Scripts.LesserElementalBolt.execute(room, mobile_ref, target_ref)
    end)
  end
end
