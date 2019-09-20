defmodule ApathyDrive.Regeneration do
  alias ApathyDrive.{Ability, Aggression, Character, Mobile, Room, TimerManager}

  @ticks_per_round 5

  def tick_time(mobile) do
    round_length = Mobile.round_length_in_ms(mobile)
    round_length / @ticks_per_round
  end

  def duration_for_energy(mobile, energy) do
    round_length = Mobile.round_length_in_ms(mobile)
    max_energy = mobile.max_energy

    max(0, trunc(round_length * energy / max_energy))
  end

  def regenerate(mobile, room) do
    mobile
    |> regenerate_energy()
    |> regenerate_hp(room)
    |> regenerate_mana(room)
    |> schedule_next_tick()
    |> Map.put(:last_tick_at, DateTime.utc_now())
    |> Mobile.update_prompt()
  end

  def decay(%{decay: true} = mobile) do
    update_in(mobile.decay_max_hp, &(&1 - 1))
  end

  def decay(%{} = mobile), do: mobile

  def energy_per_tick(mobile) do
    mobile.max_energy / @ticks_per_round
  end

  def energy_since_last_tick(%{last_tick_at: nil} = mobile), do: energy_per_tick(mobile)

  def energy_since_last_tick(%{last_tick_at: last_tick} = mobile) do
    ms_since_last_tick = DateTime.diff(DateTime.utc_now(), last_tick, :millisecond)
    energy_per_tick = energy_per_tick(mobile)
    energy = energy_per_tick * ms_since_last_tick / tick_time(mobile)

    min(energy, energy_per_tick)
  end

  def hp_since_last_tick(room, %{last_tick_at: nil} = mobile) do
    regen_per_tick(room, mobile, Mobile.hp_regen_per_round(mobile)) + heal_effect_per_tick(mobile) -
      damage_effect_per_tick(mobile)
  end

  def hp_since_last_tick(room, %{last_tick_at: last_tick} = mobile) do
    ms_since_last_tick = DateTime.diff(DateTime.utc_now(), last_tick, :millisecond)
    hp_per_tick = regen_per_tick(room, mobile, Mobile.hp_regen_per_round(mobile))

    total_hp_per_tick =
      hp_per_tick + heal_effect_per_tick(mobile) - damage_effect_per_tick(mobile)

    hp = total_hp_per_tick * ms_since_last_tick / tick_time(mobile)

    min(hp, total_hp_per_tick)
  end

  def heal_effect_per_tick(%{} = mobile) do
    Mobile.ability_value(mobile, "Heal") / @ticks_per_round
  end

  def damage_effect_per_tick(%{} = mobile) do
    Mobile.ability_value(mobile, "Damage") / @ticks_per_round
  end

  def mana_since_last_tick(room, %{last_tick_at: nil} = mobile),
    do: regen_per_tick(room, mobile, Mobile.mana_regen_per_round(mobile))

  def mana_since_last_tick(room, %{last_tick_at: last_tick} = mobile) do
    ms_since_last_tick = DateTime.diff(DateTime.utc_now(), last_tick, :millisecond)
    mana_per_tick = regen_per_tick(room, mobile, Mobile.mana_regen_per_round(mobile))
    mana = mana_per_tick * ms_since_last_tick / tick_time(mobile)

    min(mana, mana_per_tick)
  end

  def regenerate_energy(mobile) do
    energy = energy_since_last_tick(mobile)

    update_in(
      mobile,
      [Access.key!(:energy)],
      &min(mobile.max_energy, &1 + energy)
    )
  end

  def regenerate_hp(%{} = mobile, room) do
    hp = hp_since_last_tick(room, mobile)

    Mobile.shift_hp(mobile, hp)
  end

  def regenerate_mana(%{mana: 1.0} = mobile, _room), do: mobile

  def regenerate_mana(%{} = mobile, room) do
    mana = mana_since_last_tick(room, mobile)

    if Map.get(mobile, :mana_regen_attributes) do
      mobile
      |> update_in([Access.key!(:mana)], &min(1.0, &1 + mana))
      |> reset_mana_regen_attributes()
    else
      mobile
      |> update_in([Access.key!(:mana)], &min(1.0, &1 + mana))
    end
  end

  def schedule_next_tick(mobile) do
    TimerManager.send_after(mobile, {:heartbeat, tick_time(mobile), {:heartbeat, mobile.ref}})
  end

  defp reset_mana_regen_attributes(%{mana_regen_attributes: _, mana: 1.0} = mobile) do
    Map.put(mobile, :mana_regen_attributes, [])
  end

  defp reset_mana_regen_attributes(mobile), do: mobile

  def regen_per_tick(room, %Character{} = mobile, regen) do
    if is_nil(mobile.attack_target) and !Aggression.enemies_present?(room, mobile) and
         !taking_damage?(mobile) do
      regen / @ticks_per_round * 10
    else
      regen / @ticks_per_round
    end
  end

  # todo: fix combat detection for mobs for real or rethink out of combat hp regeneration
  def regen_per_tick(_room, %{} = _mobile, regen) do
    regen / @ticks_per_round
  end

  def heal_limbs(room, target_ref, percentage) do
    Room.update_mobile(room, target_ref, fn target ->
      if Map.has_key?(target, :limbs) do
        limbs =
          target.limbs
          |> Map.keys()
          |> Enum.filter(&(target.limbs[&1].health > 0 and target.limbs[&1].health < 1.0))

        Enum.reduce(limbs, room, fn limb, room ->
          percentage = percentage / length(limbs)

          heal_limb(room, target_ref, percentage, limb)
        end)
      else
        target
      end
    end)
  end

  def heal_limb(room, target_ref, percentage, limb) do
    Room.update_mobile(room, target_ref, fn target ->
      if Map.has_key?(target, :limbs) do
        initial_limb_health = target.limbs[limb].health

        target =
          update_in(
            target.limbs[limb].health,
            &min(1.0, &1 + percentage)
          )

        limb_health = target.limbs[limb].health

        if initial_limb_health < 0.5 and limb_health >= 0.5 and !target.limbs[limb].fatal do
          Mobile.send_scroll(target, "<p>Your #{limb} is no longer crippled!</p>")

          Room.send_scroll(
            room,
            "<p>#{Mobile.colored_name(target)}'s #{limb} is no longer crippled!</p>",
            [target]
          )

          Systems.Effect.remove_oldest_stack(target, {:crippled, limb})
        else
          target
        end
      else
        target
      end
    end)
  end

  def balance_limbs(room, target_ref) do
    Room.update_mobile(room, target_ref, fn target ->
      healthiest_limb =
        target.limbs
        |> Map.keys()
        |> Enum.shuffle()
        |> Enum.filter(&(target.limbs[&1].health > 0))
        |> Enum.sort_by(&{target.limbs[&1].fatal, -target.limbs[&1].health})
        |> List.first()

      target.limbs
      |> Enum.reduce(room, fn {limb_name, _limb}, room ->
        Room.update_mobile(room, target_ref, fn target ->
          limb = target.limbs[limb_name]

          cond do
            target.hp < 0 and limb_name == healthiest_limb ->
              Mobile.send_scroll(
                target,
                "<p><span class='dark-red'>You are bleeding!</span></p>"
              )

              Room.send_scroll(
                room,
                "<p><span class='dark-red'>#{Mobile.colored_name(target)} is bleeding!</span></p>",
                [target]
              )

              amount = max(0.01, 1 / Mobile.max_hp_at_level(target, target.level))

              room
              |> Room.update_mobile(target_ref, fn target ->
                update_in(target, [:hp], &(&1 + amount))
              end)
              |> Ability.damage_limb(target_ref, healthiest_limb, -amount * 2)

            is_nil(limb[:parent]) ->
              target

            limb.health < 0 ->
              Mobile.send_scroll(
                target,
                "<p><span class='dark-red'>You are bleeding!</span></p>"
              )

              Room.send_scroll(
                room,
                "<p><span class='dark-red'>#{Mobile.colored_name(target)} is bleeding!</span></p>",
                [target]
              )

              max_hp = Mobile.max_hp_at_level(target, target.level)

              if max_hp > 0 do
                amount = max(0.01, 1 / max_hp)

                room
                |> heal_limb(target.ref, amount * 2, limb_name)
                |> update_in([:mobiles, target.ref, :hp], &(&1 - amount))
                |> update_in([:mobiles, target.ref, :limbs, limb_name, :health], &min(0, &1))
              else
                room
              end

            :else ->
              target
          end
        end)
      end)
    end)
  end

  defp taking_damage?(%{} = mobile) do
    Mobile.ability_value(mobile, "Damage") > 0
  end
end
