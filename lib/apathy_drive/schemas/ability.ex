defmodule ApathyDrive.Ability do
  use ApathyDriveWeb, :model

  alias ApathyDrive.{
    Ability,
    AbilityAttribute,
    AbilityDamageType,
    AbilityTrait,
    Character,
    Companion,
    Currency,
    Directory,
    Enchantment,
    Item,
    ItemInstance,
    Match,
    Mobile,
    Monster,
    Party,
    Repo,
    Room,
    Stealth,
    Text,
    TimerManager
  }

  require Logger

  schema "abilities" do
    field(:name, :string)
    field(:targets, :string)
    field(:kind, :string)
    field(:mana, :integer, default: 0)
    field(:command, :string)
    field(:description, :string)
    field(:user_message, :string)
    field(:target_message, :string)
    field(:spectator_message, :string)
    field(:duration, :integer, default: 0)
    field(:cooldown, :integer)
    field(:cast_time, :integer)
    field(:energy, :integer, default: 1000)

    field(:traits, :map, virtual: true, default: %{})
    field(:ignores_round_cooldown?, :boolean, virtual: true, default: false)
    field(:result, :any, virtual: true)
    field(:cast_complete, :boolean, virtual: true, default: false)
    field(:skills, :any, virtual: true, default: [])
    field(:target_list, :any, virtual: true)
    field(:attributes, :map, virtual: true, default: %{})
    field(:max_stacks, :integer, virtual: true, default: 1)
    field(:chance, :integer, virtual: true)
    field(:on_hit?, :boolean, virtual: true, default: false)
    field(:can_crit, :boolean, virtual: true, default: false)

    has_many(:monsters_abilities, ApathyDrive.MonsterAbility)
    has_many(:monsters, through: [:monsters_abilities, :monster])

    has_many(:abilities_traits, ApathyDrive.AbilityTrait)
    has_many(:trait_records, through: [:abilities_traits, :trait])

    has_many(:abilities_damage_types, ApathyDrive.AbilityDamageType)
    has_many(:damage_types, through: [:abilities_damage_types, :damage_types])

    timestamps()
  end

  @required_fields ~w(name targets kind command description user_message target_message spectator_message)a
  @optional_fields ~w(cast_time cooldown duration mana)a

  @valid_targets [
    "monster or single",
    "self",
    "self or single",
    "monster",
    "full party area",
    "full attack area",
    "single",
    "full area",
    "weapon"
  ]
  @target_required_targets ["monster or single", "monster", "single"]

  @kinds ["heal", "attack", "auto attack", "curse", "utility", "blessing", "passive"]

  @instant_traits [
    "CurePoison",
    "Damage",
    "DispelMagic",
    "Enslave",
    "Freedom",
    "Heal",
    "HealMana",
    "KillSpell",
    "Poison",
    "RemoveSpells",
    "Script",
    "Summon",
    "Teleport"
  ]

  @duration_traits [
    "AC",
    "Accuracy",
    "Agility",
    "Charm",
    "Blind",
    "Charm",
    "Confusion",
    "ConfusionMessage",
    "ConfusionSpectatorMessage",
    "Crits",
    "Damage",
    "DamageShield",
    "DamageShieldUserMessage",
    "DamageShieldTargetMessage",
    "DamageShieldSpectatorMessage",
    "DarkVision",
    "Dodge",
    "Encumbrance",
    "EndCast",
    "EndCast%",
    "EnhanceSpell",
    "EnhanceSpellDamage",
    "Fear",
    "Heal",
    "Health",
    "HPRegen",
    "Intellect",
    "Light",
    "LightVision",
    "MagicalResist",
    "ManaRegen",
    "MaxHP",
    "MaxMana",
    "ModifyDamage",
    "Perception",
    "Picklocks",
    "PoisonImmunity",
    "RemoveMessage",
    "ResistCold",
    "ResistFire",
    "ResistLightning",
    "ResistStone",
    "Root",
    "SeeHidden",
    "Shadowform",
    "Silence",
    "Speed",
    "Spellcasting",
    "StatusMessage",
    "Stealth",
    "Strength",
    "Tracking",
    "Willpower"
  ]

  @resist_message %{
    user: "You attempt to cast {{ability}} on {{target}}, but they resist!",
    target: "{{user}} attempts to cast {{ability}} on you, but you resist!",
    spectator: "{{user}} attempts to cast {{ability}} on {{target}}, but they resist!"
  }

  @deflect_message %{
    user: "{{target}}'s armour deflects your feeble attack!",
    target: "Your armour deflects {{user}}'s feeble attack!",
    spectator: "{{target}}'s armour deflects {{user}}'s feeble attack!"
  }

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ %{}) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def data_for_admin_index do
    __MODULE__
    |> select(
      [dt],
      map(
        dt,
        ~w(id name targets kind mana command description user_message target_message spectator_message duration cooldown cast_time)a
      )
    )
  end

  def total_damage(%Ability{traits: %{"Damage" => damage}}) do
    damage
    |> Enum.map(& &1.damage)
    |> Enum.sum()
  end

  def total_damage(%Ability{}), do: 0

  def valid_targets, do: @valid_targets
  def kinds, do: @kinds

  def set_description_changeset(model, description) do
    model
    |> cast(%{description: description}, [:description])
    |> validate_required(:description)
    |> validate_length(:description, min: 20, max: 500)
  end

  def set_duration_changeset(model, duration) do
    model
    |> cast(%{duration: duration}, [:duration])
    |> validate_required(:duration)
    |> validate_number(:duration, greater_than: 0)
  end

  def set_mana_changeset(model, mana) do
    model
    |> cast(%{mana: mana}, [:mana])
    |> validate_required(:mana)
    |> validate_number(:mana, greater_than: 0)
  end

  def set_cast_time_changeset(model, cast_time) do
    model
    |> cast(%{cast_time: cast_time}, [:cast_time])
    |> validate_required(:cast_time)
    |> validate_number(:cast_time, greater_than_or_equal_to: 0)
  end

  def set_user_message_changeset(model, message) do
    model
    |> cast(%{user_message: message}, [:user_message])
    |> validate_required(:user_message)
  end

  def set_command_changeset(model, command) do
    model
    |> cast(%{command: command}, [:command])
    |> validate_required(:command)
    |> validate_length(:command, min: 3, max: 10)
  end

  def set_target_message_changeset(model, message) do
    model
    |> cast(%{target_message: message}, [:target_message])
    |> validate_required(:target_message)
  end

  def set_spectator_message_changeset(model, message) do
    model
    |> cast(%{spectator_message: message}, [:spectator_message])
    |> validate_required(:spectator_message)
  end

  def set_targets_changeset(model, targets) do
    model
    |> cast(%{targets: targets}, [:targets])
    |> validate_required(:targets)
    |> validate_inclusion(:targets, @valid_targets)
  end

  def set_kind_changeset(model, kind) do
    model
    |> cast(%{kind: kind}, [:kind])
    |> validate_required(:kind)
    |> validate_inclusion(:kind, @kinds)
  end

  def find(id) do
    ability = ApathyDrive.Repo.get(__MODULE__, id)

    if ability do
      put_in(ability.traits, AbilityTrait.load_traits(id))

      case AbilityDamageType.load_damage(id) do
        [] ->
          ability

        damage ->
          update_in(ability.traits, &Map.put(&1, "Damage", damage))
      end
    end
  end

  def match_by_name(name, all \\ false) do
    abilities =
      if all do
        learnable_abilities()
      else
        __MODULE__
        |> where([ability], not is_nil(ability.name) and ability.name != "")
        |> distinct(true)
        |> ApathyDrive.Repo.all()
      end
      |> Enum.map(fn ability ->
        attributes = AbilityAttribute.load_attributes(ability.id)
        Map.put(ability, :attributes, attributes)
      end)

    Match.all(abilities, :keyword_starts_with, name)
  end

  def learnable_abilities do
    class_ability_ids =
      ApathyDrive.ClassAbility
      |> select([:ability_id])
      |> distinct(true)
      |> preload(:ability)
      |> Repo.all()

    learn_id =
      ApathyDrive.ItemAbilityType
      |> select([:id])
      |> where(name: "Learn")
      |> Repo.one!()
      |> Map.get(:id)

    scroll_ability_ids =
      ApathyDrive.ItemAbility
      |> select([:ability_id])
      |> where(type_id: ^learn_id)
      |> distinct(true)
      |> preload(:ability)
      |> Repo.all()

    (class_ability_ids ++ scroll_ability_ids)
    |> Enum.map(& &1.ability)
    |> Enum.uniq()
    |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))
  end

  def heal_abilities(%{abilities: abilities} = mobile) do
    abilities
    |> Map.values()
    |> Enum.filter(&(&1.kind == "heal"))
    |> useable(mobile)
  end

  def drain_abilities(%{abilities: abilities} = mobile, %{} = target) do
    abilities
    |> Map.values()
    |> Enum.filter(fn ability ->
      Map.has_key?(ability.traits, "Damage") and
        Enum.any?(ability.traits["Damage"], &(&1.kind == "drain"))
    end)
    |> Enum.filter(fn ability ->
      Ability.affects_target?(target, ability)
    end)
    |> useable(mobile)
  end

  def bless_abilities(%{abilities: abilities} = mobile, %{} = target) do
    abilities
    |> Map.values()
    |> Enum.filter(&(&1.kind == "blessing"))
    |> Enum.reject(fn ability ->
      Ability.removes_blessing?(target, ability) or
        Character.wearing_enchanted_item?(mobile, ability)
    end)
    |> useable(mobile)
  end

  def curse_abilities(%{abilities: abilities} = mobile, %{} = target) do
    abilities
    |> Map.values()
    |> Enum.filter(&(&1.kind == "curse"))
    |> Enum.reject(fn ability ->
      Ability.removes_blessing?(target, ability)
    end)
    |> useable(mobile)
  end

  def attack_abilities(%{abilities: abilities} = mobile, %{} = target) do
    abilities
    |> Map.values()
    |> Enum.filter(&(&1.kind == "attack"))
    |> Enum.filter(fn ability ->
      Ability.affects_target?(target, ability)
    end)
    |> useable(mobile)
  end

  def useable(abilities, %{} = mobile) do
    abilities
    |> Enum.reject(fn ability ->
      ability.mana > 0 && !Mobile.enough_mana_for_ability?(mobile, ability)
    end)
  end

  def removes_blessing?(%{} = mobile, %{} = ability) do
    abilities = ability.traits["RemoveSpells"] || []

    Systems.Effect.max_stacks?(mobile, ability) or
      Enum.any?(abilities, fn ability_id ->
        Systems.Effect.stack_count(mobile, ability_id) > 0
      end)
  end

  def removes_blessing?(mobile, ability) do
    Systems.Effect.max_stacks?(mobile, ability)
  end

  def execute(%Room{} = room, caster_ref, %Ability{targets: targets}, "")
      when targets in @target_required_targets do
    room
    |> Room.get_mobile(caster_ref)
    |> Mobile.send_scroll(
      "<p><span class='red'>You must specify a target for that ability.</span></p>"
    )

    room
  end

  def execute(%Room{} = room, caster_ref, %Ability{} = ability, query) when is_binary(query) do
    case get_targets(room, caster_ref, ability, query) do
      [] ->
        case query do
          "" ->
            if ability.targets in ["self", "self or single"] do
              execute(room, caster_ref, ability, List.wrap(caster_ref))
            else
              room
              |> Room.get_mobile(caster_ref)
              |> Mobile.send_scroll("<p>Your ability would affect no one.</p>")

              room
            end

          _ ->
            if item = item_target(room, caster_ref, query) do
              execute(room, caster_ref, ability, item)
            else
              room
              |> Room.get_mobile(caster_ref)
              |> Mobile.send_scroll(
                "<p><span class='cyan'>Can't find #{query} here! Your spell fails.</span></p>"
              )

              room
            end
        end

      targets ->
        execute(room, caster_ref, ability, targets)
    end
  end

  def execute(%Room{} = room, caster_ref, %Ability{} = ability, %Item{} = item) do
    traits =
      ability.traits
      |> Map.update("RequireItems", [item.instance_id], &[item.instance_id | &1])
      |> Map.put(
        "TickMessage",
        "<p><span class='dark-cyan'>You continue enchanting the #{item.name}.</span></p>"
      )

    ability = Map.put(ability, :traits, traits)

    Room.update_mobile(room, caster_ref, fn caster ->
      cond do
        mobile = not_enough_energy(caster, Map.put(ability, :target_list, item)) ->
          mobile

        can_execute?(room, caster, ability) ->
          display_pre_cast_message(room, caster, item, ability)

          room =
            Room.update_mobile(room, caster.ref, fn caster ->
              caster =
                caster
                |> apply_cooldowns(ability)
                |> Mobile.subtract_mana(ability)
                |> Mobile.subtract_energy(ability)
                |> Stealth.reveal()

              Mobile.update_prompt(caster)

              caster =
                if lt = Enum.find(TimerManager.timers(caster), &match?({:longterm, _}, &1)) do
                  Mobile.send_scroll(
                    caster,
                    "<p><span class='cyan'>You interrupt your work.</span></p>"
                  )

                  TimerManager.cancel(caster, lt)
                else
                  caster
                end

              case Repo.get_by(
                     Enchantment,
                     items_instances_id: item.instance_id,
                     ability_id: ability.id
                   ) do
                %Enchantment{finished: true} = enchantment ->
                  Repo.delete!(enchantment)

                  Mobile.send_scroll(
                    caster,
                    "<p><span class='blue'>You've removed #{ability.name} from #{item.name}.</span></p>"
                  )

                  Character.load_items(caster)

                %Enchantment{finished: false} = enchantment ->
                  enchantment = Map.put(enchantment, :ability, ability)
                  time = Enchantment.next_tick_time(enchantment)

                  Mobile.send_scroll(
                    caster,
                    "<p><span class='cyan'>You continue your work.</span></p>"
                  )

                  Mobile.send_scroll(
                    caster,
                    "<p><span class='dark-green'>Time Left:</span> <span class='dark-cyan'>#{
                      Enchantment.time_left(enchantment) |> Enchantment.formatted_time_left()
                    }</span></p>"
                  )

                  TimerManager.send_after(
                    caster,
                    {{:longterm, item.instance_id}, :timer.seconds(time),
                     {:lt_tick, time, caster_ref, enchantment}}
                  )

                nil ->
                  enchantment =
                    %Enchantment{items_instances_id: item.instance_id, ability_id: ability.id}
                    |> Repo.insert!()
                    |> Map.put(:ability, ability)

                  time = Enchantment.next_tick_time(enchantment)
                  Mobile.send_scroll(caster, "<p><span class='cyan'>You begin work.</span></p>")

                  Mobile.send_scroll(
                    caster,
                    "<p><span class='dark-green'>Time Left:</span> <span class='dark-cyan'>#{
                      Enchantment.time_left(enchantment) |> Enchantment.formatted_time_left()
                    }</span></p>"
                  )

                  TimerManager.send_after(
                    caster,
                    {{:longterm, item.instance_id}, :timer.seconds(time),
                     {:lt_tick, time, caster_ref, enchantment}}
                  )
              end
            end)

          Room.update_moblist(room)

          Room.update_energy_bar(room, caster.ref)
          Room.update_hp_bar(room, caster.ref)
          Room.update_mana_bar(room, caster.ref)

          room

        :else ->
          room
      end
    end)
  end

  def execute(%Room{} = room, caster_ref, %Ability{} = ability, targets) when is_list(targets) do
    Room.update_mobile(room, caster_ref, fn caster ->
      cond do
        mobile = not_enough_energy(caster, Map.put(ability, :target_list, targets)) ->
          mobile

        can_execute?(room, caster, ability) ->
          display_pre_cast_message(room, caster, targets, ability)

          ability = crit(caster, ability)

          room =
            Enum.reduce(targets, room, fn target_ref, updated_room ->
              Room.update_mobile(updated_room, target_ref, fn target ->
                caster = updated_room.mobiles[caster.ref]

                if affects_target?(target, ability) do
                  updated_room = apply_ability(updated_room, caster, target, ability)

                  target = updated_room.mobiles[target_ref]

                  if target do
                    target =
                      if ability.kind in ["attack", "curse"] do
                        Stealth.reveal(target)
                      else
                        target
                      end

                    target_level = Mobile.target_level(caster, target)
                    max_hp = Mobile.max_hp_at_level(target, target_level)
                    hp = trunc(max_hp * target.hp)

                    if hp < 1 do
                      Mobile.die(target, updated_room)
                    else
                      put_in(updated_room.mobiles[target.ref], target)
                    end
                  else
                    updated_room
                  end
                else
                  message =
                    "#{target.name} is not affected by that ability." |> Text.capitalize_first()

                  Mobile.send_scroll(caster, "<p><span class='cyan'>#{message}</span></p>")
                  target
                end
              end)
            end)

          Room.update_moblist(room)

          room =
            Room.update_mobile(room, caster.ref, fn caster ->
              caster =
                caster
                |> apply_cooldowns(ability)
                |> Mobile.subtract_mana(ability)
                |> Mobile.subtract_energy(ability)

              Mobile.update_prompt(caster)

              if ability.kind in ["attack", "curse"] and !(caster.ref in targets) do
                [target_ref | _] = targets

                if Map.has_key?(caster, :attack_target) do
                  if is_nil(caster.attack_target) do
                    caster
                    |> Map.put(:attack_target, target_ref)
                    |> Mobile.send_scroll(
                      "<p><span class='dark-yellow'>*Combat Engaged*</span></p>"
                    )
                  else
                    caster
                    |> Map.put(:attack_target, target_ref)
                  end
                else
                  caster
                end
              else
                caster
              end
            end)

          Room.update_energy_bar(room, caster.ref)
          Room.update_hp_bar(room, caster.ref)
          Room.update_mana_bar(room, caster.ref)

          room = Room.update_mobile(room, caster_ref, &Stealth.reveal(&1))

          Room.update_moblist(room)

          room =
            if instance_id = ability.traits["DestroyItem"] do
              Room.update_mobile(room, caster_ref, fn caster ->
                scroll =
                  (caster.inventory ++ caster.equipment)
                  |> Enum.find(&(&1.instance_id == instance_id))

                Mobile.send_scroll(
                  caster,
                  "<p>As you read the #{scroll.name} it crumbles to dust.</p>"
                )

                ItemInstance
                |> Repo.get!(instance_id)
                |> Repo.delete!()

                caster
                |> Character.load_abilities()
                |> Character.load_items()
              end)
            else
              room
            end

          if (on_hit = ability.traits["OnHit"]) && is_nil(Process.get(:ability_result)) do
            Process.delete(:ability_result)
            execute(room, caster_ref, on_hit, targets)
          else
            Process.delete(:ability_result)
            room
          end

        :else ->
          room
      end
    end)
  end

  def not_enough_energy(%{energy: energy} = caster, %{energy: req_energy} = ability) do
    if req_energy > energy && !ability.on_hit? do
      if caster.casting do
        Mobile.send_scroll(
          caster,
          "<p><span class='dark-red'>You interrupt your other spell.</span></p>"
        )
      end

      if ability.mana > 0 do
        Mobile.send_scroll(caster, "<p><span class='cyan'>You begin your casting.</span></p>")
      else
        Mobile.send_scroll(caster, "<p><span class='cyan'>You move into position...</span></p>")
      end

      Map.put(caster, :casting, ability)
    end
  end

  def duration(%Ability{duration: duration} = ability, %{} = caster, %{} = target, _room) do
    if duration > 0 do
      caster_level = Mobile.caster_level(caster, target)

      caster_sc = Mobile.spellcasting_at_level(caster, caster_level, ability)

      trunc(duration * :math.pow(1.005, caster_sc))
    else
      duration
    end
  end

  def dodged?(%{} = caster, %{} = target, room) do
    caster_level = Mobile.caster_level(caster, target)
    accuracy = Mobile.accuracy_at_level(caster, caster_level, room)

    target_level = Mobile.target_level(caster, target)
    dodge = Mobile.dodge_at_level(target, target_level, room)

    modifier = Mobile.ability_value(target, "Dodge")

    difference = dodge - accuracy

    chance =
      if difference > 0 do
        30 + modifier + difference * 0.3
      else
        30 + modifier + difference * 0.7
      end

    :rand.uniform(100) < chance
  end

  def blocked?(%{} = caster, %Character{} = target, room) do
    if Character.shield(target) do
      caster_level = Mobile.caster_level(caster, target)
      accuracy = Mobile.accuracy_at_level(caster, caster_level, room)

      target_level = Mobile.target_level(caster, target)
      block = Mobile.block_at_level(target, target_level)

      modifier = Mobile.ability_value(target, "Block")

      difference = block - accuracy

      chance =
        if difference > 0 do
          30 + modifier + difference * 0.3
        else
          30 + modifier + difference * 0.7
        end

      :rand.uniform(100) < chance
    else
      false
    end
  end

  def blocked?(%{} = _caster, %{} = target, _room) do
    :rand.uniform(100) < Mobile.ability_value(target, "Block")
  end

  def parried?(%{} = caster, %Character{} = target, room) do
    if Character.weapon(target) do
      caster_level = Mobile.caster_level(caster, target)
      accuracy = Mobile.accuracy_at_level(caster, caster_level, room)

      target_level = Mobile.target_level(caster, target)
      dodge = Mobile.parry_at_level(target, target_level)

      modifier = Mobile.ability_value(target, "Parry")

      difference = dodge - accuracy

      chance =
        if difference > 0 do
          30 + modifier + difference * 0.3
        else
          30 + modifier + difference * 0.7
        end

      :rand.uniform(100) < chance
    else
      false
    end
  end

  def parried?(%{} = _caster, %{} = target, _room) do
    :rand.uniform(100) < Mobile.ability_value(target, "Parry")
  end

  def apply_ability(
        %Room{} = room,
        %{} = caster,
        %{} = target,
        %Ability{traits: %{"Dodgeable" => true}} = ability
      ) do
    cond do
      dodged?(caster, target, room) ->
        Process.put(:ability_result, :dodged)
        display_cast_message(room, caster, target, Map.put(ability, :result, :dodged))

        target =
          target
          |> aggro_target(ability, caster)
          |> Character.add_attribute_experience(%{
            agility: 0.9,
            charm: 0.1
          })

        put_in(room.mobiles[target.ref], target)

      blocked?(caster, target, room) ->
        Process.put(:ability_result, :blocked)
        display_cast_message(room, caster, target, Map.put(ability, :result, :blocked))

        target =
          target
          |> aggro_target(ability, caster)
          |> Character.add_attribute_experience(%{
            strength: 0.7,
            agility: 0.2,
            charm: 0.1
          })

        put_in(room.mobiles[target.ref], target)

      parried?(caster, target, room) ->
        Process.put(:ability_result, :parried)
        display_cast_message(room, caster, target, Map.put(ability, :result, :parried))

        target =
          target
          |> aggro_target(ability, caster)
          |> Character.add_attribute_experience(%{
            strength: 0.2,
            agility: 0.7,
            charm: 0.1
          })

        put_in(room.mobiles[target.ref], target)

      true ->
        apply_ability(
          room,
          caster,
          target,
          update_in(ability.traits, &Map.delete(&1, "Dodgeable"))
        )
    end
  end

  def apply_ability(
        %Room{} = room,
        %Character{} = caster,
        %{} = target,
        %Ability{traits: %{"Enslave" => _}} = ability
      ) do
    display_cast_message(room, caster, target, ability)

    if companion = Character.companion(caster, room) do
      companion
      |> Companion.dismiss(room)
      |> Companion.convert_for_character(target, caster)
    else
      Companion.convert_for_character(room, target, caster)
    end
  end

  def apply_ability(%Room{} = room, %{} = caster, %{} = target, %Ability{} = ability) do
    {caster, target} =
      target
      |> apply_instant_traits(ability, caster, room)

    target = aggro_target(target, ability, caster)

    room = put_in(room.mobiles[caster.ref], caster)
    room = put_in(room.mobiles[target.ref], target)

    duration = duration(ability, caster, target, room)

    if ability.kind == "curse" and duration < 1 do
      Process.put(:ability_result, :resisted)
      display_cast_message(room, caster, target, Map.put(ability, :result, :resisted))

      target =
        target
        |> Map.put(:ability_shift, nil)
        |> Map.put(:ability_special, nil)
        |> Mobile.update_prompt()

      room
      |> put_in([:mobiles, target.ref], target)
    else
      display_cast_message(room, caster, target, ability)

      room
      |> trigger_damage_shields(caster.ref, target.ref, ability)
      |> finish_ability(caster.ref, target.ref, ability, target.ability_shift)
    end
  end

  def finish_ability(room, caster_ref, target_ref, ability, ability_shift) do
    room =
      Room.update_mobile(room, target_ref, fn target ->
        caster = room.mobiles[caster_ref]

        duration = duration(ability, caster, target, room)

        target =
          if ability_shift do
            Mobile.shift_hp(target, ability_shift, room)
          else
            target
          end

        target
        |> Map.put(:ability_shift, nil)
        |> Map.put(:ability_special, nil)
        |> apply_duration_traits(ability, caster, duration, room)
        |> Mobile.update_prompt()
      end)

    room =
      if script_id = ability.traits["Script"] do
        Room.update_mobile(room, caster_ref, fn caster ->
          ApathyDrive.Script.execute_script(room, caster, script_id)
        end)
      else
        room
      end

    Room.update_hp_bar(room, target_ref)
    Room.update_hp_bar(room, caster_ref)
    Room.update_mana_bar(room, caster_ref)
    Room.update_mana_bar(room, target_ref)

    room
  end

  def trigger_damage_shields(%Room{} = room, caster_ref, target_ref, _ability)
      when target_ref == caster_ref,
      do: room

  def trigger_damage_shields(%Room{} = room, caster_ref, target_ref, ability) do
    if (target = room.mobiles[target_ref]) && "Damage" in Map.keys(ability.traits) do
      target
      |> Map.get(:effects)
      |> Map.values()
      |> Enum.filter(&Map.has_key?(&1, "DamageShield"))
      |> Enum.reduce(room, fn %{"DamageShield" => _, "Damage" => damage} = shield, updated_room ->
        reaction = %Ability{
          kind: "attack",
          mana: 0,
          energy: 0,
          user_message: shield["DamageShieldUserMessage"],
          target_message: shield["DamageShieldTargetMessage"],
          spectator_message: shield["DamageShieldSpectatorMessage"],
          traits: %{
            "Damage" => damage
          }
        }

        apply_ability(updated_room, room.mobiles[target_ref], room.mobiles[caster_ref], reaction)
      end)
    else
      room
    end
  end

  def aggro_target(
        %Character{ref: target_ref} = target,
        %Ability{kind: kind},
        %{ref: caster_ref} = _caster
      )
      when kind in ["attack", "curse"] and target_ref != caster_ref do
    # players don't automatically fight back
    target
  end

  def aggro_target(%{ref: target_ref} = target, %Ability{kind: kind}, %{ref: caster_ref} = caster)
      when kind in ["attack", "curse"] and target_ref != caster_ref do
    ApathyDrive.Aggression.attack_target(target, caster)
  end

  def aggro_target(%{} = target, %Ability{}, %{} = _caster), do: target

  def apply_instant_traits(%{} = target, %Ability{} = ability, %{} = caster, room) do
    ability.traits
    |> Map.take(@instant_traits)
    |> Enum.reduce({caster, target}, fn trait, {updated_caster, updated_target} ->
      apply_instant_trait(trait, updated_target, ability, updated_caster, room)
    end)
  end

  def apply_instant_trait({"RemoveSpells", ability_ids}, %{} = target, _ability, caster, _room) do
    target =
      Enum.reduce(ability_ids, target, fn ability_id, updated_target ->
        Systems.Effect.remove_oldest_stack(updated_target, ability_id)
      end)

    {caster, target}
  end

  def apply_instant_trait({"Heal", value}, %{} = target, _ability, caster, _room)
      when is_float(value) do
    {caster, Map.put(target, :ability_shift, value)}
  end

  def apply_instant_trait({"Heal", value}, %{} = target, ability, caster, _room) do
    roll = Enum.random(value["min"]..value["max"])

    attribute_value = Mobile.spellcasting_at_level(caster, caster.level, ability)

    modifier = (attribute_value + 50) / 100

    healing = roll * modifier

    percentage_healed = healing / Mobile.max_hp_at_level(target, target.level)

    {caster, Map.put(target, :ability_shift, percentage_healed)}
  end

  def apply_instant_trait({"Damage", value}, %{} = target, _ability, caster, _room)
      when is_float(value) do
    {caster, Map.put(target, :ability_shift, -value)}
  end

  def apply_instant_trait({"Damage", damages}, %{} = target, ability, caster, room) do
    caster_level = Mobile.caster_level(caster, target)
    target_level = Mobile.target_level(caster, target)

    round_percent = ability.energy / caster.max_energy

    target =
      target
      |> Map.put(:ability_shift, 0)

    total_min = Enum.reduce(damages, 0, &(&1.min + &2))
    total_max = Enum.reduce(damages, 0, &(&1.max + &2))

    {caster, damage_percent} =
      Enum.reduce(damages, {caster, 0}, fn
        %{kind: "physical", min: min, max: max, damage_type: type}, {caster, damage_percent} ->
          modifier = (min + max) / (total_min + total_max)

          caster_damage =
            trunc(
              Mobile.physical_damage_at_level(caster, caster_level) * round_percent * modifier
            )

          ability_damage = Enum.random(min..max)

          resist = Mobile.physical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = (caster_damage + ability_damage) * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          {caster, damage_percent + percent}

        %{kind: "physical", damage: dmg, damage_type: type}, {caster, damage_percent} ->
          resist = Mobile.physical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = dmg * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          {caster, damage_percent + percent}

        %{kind: "magical", min: min, max: max, damage_type: type}, {caster, damage_percent} ->
          modifier = (min + max) / (total_min + total_max)

          caster_damage =
            trunc(Mobile.magical_damage_at_level(caster, caster_level) * round_percent * modifier)

          ability_damage = Enum.random(min..max)

          resist = Mobile.magical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = (caster_damage + ability_damage) * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          {caster, damage_percent + percent}

        %{kind: "magical", damage: damage, damage_type: type}, {caster, damage_percent} ->
          resist = Mobile.magical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = damage * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          {caster, damage_percent + percent}

        %{kind: "drain", min: min, max: max, damage_type: type}, {caster, damage_percent} ->
          modifier = (min + max) / (total_min + total_max)

          caster_damage =
            trunc(Mobile.magical_damage_at_level(caster, caster_level) * round_percent * modifier)

          ability_damage = Enum.random(min..max)

          resist = Mobile.magical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = (caster_damage + ability_damage) * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          heal_percent = damage / Mobile.max_hp_at_level(caster, caster_level)

          caster = Mobile.shift_hp(caster, heal_percent, room)

          Mobile.update_prompt(caster)

          {caster, damage_percent + percent}
      end)

    damage_percent =
      if match?(%Character{}, target) and target.level < 5 and damage_percent > 0.2 do
        Enum.random(10..20) / 100
      else
        damage_percent
      end

    target =
      target
      |> Map.put(:ability_special, :normal)
      |> Map.update(:ability_shift, 0, &(&1 - damage_percent))

    target_attribute =
      if ability.mana > 0 do
        :willpower
      else
        :strength
      end

    target =
      Character.add_attribute_experience(target, %{
        target_attribute => 0.2,
        :health => 0.8
      })

    case {caster, target} do
      {%Character{bounty: bounty} = caster, %Character{bounty: target_bounty} = target} ->
        percent = 1 / (target.hp / abs(damage_percent))

        cond do
          target_bounty < 0 ->
            initial_caster_legal_status = Character.legal_status(caster)

            Logger.info(
              "increasing #{caster.name}'s bounty by #{trunc(abs(target_bounty) * abs(percent))} (#{
                abs(target_bounty)
              } * #{abs(percent)}) (#{target.hp} / #{abs(damage_percent)})"
            )

            new_bounty =
              min(abs(target_bounty), max(bounty, 0) + trunc(abs(target_bounty) * abs(percent)))

            caster =
              caster
              |> Ecto.Changeset.change(%{
                bounty: new_bounty
              })
              |> Repo.update!()

            Directory.add_character(%{
              name: caster.name,
              bounty: caster.bounty,
              room: caster.room_id,
              ref: caster.ref,
              title: caster.title
            })

            caster_legal_status = Character.legal_status(caster)

            if caster_legal_status != initial_caster_legal_status do
              color = ApathyDrive.Commands.Who.color(caster_legal_status)

              status = "<span class='#{color}'>#{caster_legal_status}</span>"

              Mobile.send_scroll(
                caster,
                "<p>Your legal status has changed to #{status}.</p>"
              )

              Room.send_scroll(
                room,
                "<p>#{Mobile.colored_name(caster)}'s legal status has changed to #{status}.",
                [caster]
              )
            end

            {caster, target}

          target_bounty > 0 ->
            bounty = trunc(abs(target_bounty) * abs(percent))
            copper = min(bounty, Currency.wealth(target))

            if copper > 0 do
              initial_caster_legal_status = Character.legal_status(caster)
              initial_target_legal_status = Character.legal_status(target)

              currency = Currency.set_value(copper)
              caster_currency = Currency.add(caster, copper)
              target_currency = Currency.subtract(target, copper)

              new_caster_bounty =
                if caster.bounty > 0 do
                  max(0, caster.bounty - copper)
                else
                  caster.bounty
                end

              caster =
                caster
                |> Ecto.Changeset.change(%{
                  bounty: new_caster_bounty,
                  runic: caster_currency.runic,
                  platinum: caster_currency.platinum,
                  gold: caster_currency.gold,
                  silver: caster_currency.silver,
                  copper: caster_currency.copper
                })
                |> Repo.update!()

              target =
                target
                |> Ecto.Changeset.change(%{
                  bounty: target_bounty - copper,
                  runic: target_currency.runic,
                  platinum: target_currency.platinum,
                  gold: target_currency.gold,
                  silver: target_currency.silver,
                  copper: target_currency.copper
                })
                |> Repo.update!()

              Directory.add_character(%{
                name: caster.name,
                bounty: caster.bounty,
                room: caster.room_id,
                ref: caster.ref,
                title: caster.title
              })

              Directory.add_character(%{
                name: target.name,
                bounty: target.bounty,
                room: target.room_id,
                ref: target.ref,
                title: target.title
              })

              Mobile.send_scroll(
                caster,
                "<p>You receive #{Currency.to_string(currency)} from #{
                  Mobile.colored_name(target)
                }'s bounty."
              )

              Mobile.send_scroll(
                target,
                "<p>#{Mobile.colored_name(caster)} receives #{Currency.to_string(currency)} from your bounty."
              )

              Room.send_scroll(
                room,
                "<p>#{Mobile.colored_name(caster)} receives #{Currency.to_string(currency)} from #{
                  Mobile.colored_name(target)
                }'s bounty.",
                [caster, target]
              )

              caster_legal_status = Character.legal_status(caster)
              target_legal_status = Character.legal_status(target)

              if caster_legal_status != initial_caster_legal_status do
                color = ApathyDrive.Commands.Who.color(caster_legal_status)

                status = "<span class='#{color}'>#{caster_legal_status}</span>"

                Mobile.send_scroll(
                  caster,
                  "<p>Your legal status has changed to #{status}.</p>"
                )

                Room.send_scroll(
                  room,
                  "<p>#{Mobile.colored_name(caster)}'s legal status has changed to #{status}.",
                  [caster]
                )
              end

              if target_legal_status != initial_target_legal_status do
                color = ApathyDrive.Commands.Who.color(target_legal_status)

                status = "<span class='#{color}'>#{target_legal_status}</span>"

                Mobile.send_scroll(
                  target,
                  "<p>Your legal status has changed to #{status}.</p>"
                )

                Room.send_scroll(
                  room,
                  "<p>#{Mobile.colored_name(target)}'s legal status has changed to #{status}.",
                  [target]
                )
              end

              {caster, target}
            else
              {caster, target}
            end

          :else ->
            {caster, target}
        end

      {caster, target} ->
        {caster, target}
    end
  end

  # just to silence the Not Implemented, handled elsewhere
  def apply_instant_trait({"Script", _id}, %{} = target, _ability, caster, _room) do
    {caster, target}
  end

  def apply_instant_trait({ability_name, _value}, %{} = target, _ability, caster, _room) do
    Mobile.send_scroll(caster, "<p><span class='red'>Not Implemented: #{ability_name}")
    {caster, target}
  end

  def raw_damage(%{kind: "physical", level: level}, caster, caster_level) do
    Mobile.physical_damage_at_level(caster, min(caster_level, level))
  end

  def raw_damage(%{kind: "physical"}, caster, caster_level) do
    Mobile.physical_damage_at_level(caster, caster_level)
  end

  def raw_damage(%{level: level}, caster, caster_level) do
    Mobile.magical_damage_at_level(caster, min(caster_level, level))
  end

  def raw_damage(%{}, caster, caster_level) do
    Mobile.magical_damage_at_level(caster, caster_level)
  end

  def crit(caster, %Ability{can_crit: true, traits: %{"Damage" => _}} = ability) do
    crit_chance = Mobile.crits_at_level(caster, caster.level)

    crit_message = fn message ->
      message
      |> String.split(" ")
      |> List.insert_at(1, "critically")
      |> Enum.join(" ")
    end

    if :rand.uniform(100) < crit_chance do
      ability
      |> update_in([Access.key!(:traits), "Damage"], fn damages ->
        Enum.map(damages, fn damage ->
          damage
          |> Map.put(:max, damage.max * 2)
          |> Map.put(:min, damage.min * 2)
        end)
      end)
      |> Map.update!(:spectator_message, &crit_message.(&1))
      |> Map.update!(:target_message, &crit_message.(&1))
      |> Map.update!(:user_message, &crit_message.(&1))
    else
      ability
    end
  end

  def crit(_caster, ability), do: ability

  def calculate_healing(damage, modifier) do
    damage * (modifier / 100) * (Enum.random(95..105) / 100)
  end

  def apply_item_enchantment(%Item{} = item, %Ability{} = ability) do
    effects =
      ability.traits
      |> Map.take(@duration_traits)
      |> Map.put("stack_key", ability.id)
      |> Map.put("stack_count", 1)
      |> Map.put("effect_ref", make_ref())

    Systems.Effect.add(item, effects)
  end

  def apply_duration_traits(%{} = target, %Ability{} = ability, %{} = caster, duration, room) do
    if !Character.wearing_enchanted_item?(target, ability) do
      effects =
        ability.traits
        |> Map.take(@duration_traits)
        |> Map.put("stack_key", ability.id)
        |> Map.put("stack_count", 1)
        |> process_duration_traits(target, caster, ability, room)
        |> Map.put("effect_ref", make_ref())

      if message = effects["StatusMessage"] do
        Mobile.send_scroll(
          target,
          "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
        )
      end

      target
      |> Systems.Effect.add(effects, :timer.seconds(duration))
      |> Systems.Effect.schedule_next_periodic_effect()
    else
      target
    end
  end

  def process_duration_traits(effects, target, caster, ability, room) do
    effects
    |> Enum.reduce(effects, fn effect, updated_effects ->
      process_duration_trait(effect, updated_effects, target, caster, ability, room)
    end)
  end

  def process_duration_trait(
        {"Damage", _damages},
        %{"DamageShield" => _} = effects,
        _target,
        _caster,
        _ability,
        _room
      ) do
    effects
  end

  def process_duration_trait({"Damage", damages}, effects, _target, _caster, _ability, _room)
      when is_float(damages) do
    effects
  end

  def process_duration_trait({"Damage", damages}, effects, target, caster, _ability, _room) do
    target_level = Mobile.target_level(caster, target)

    damage_percent =
      Enum.reduce(damages, 0, fn
        %{kind: "physical", min: min, max: max, damage_type: type}, damage_percent ->
          ability_damage = Enum.random(min..max)

          resist = Mobile.physical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = ability_damage * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          damage_percent + percent

        %{kind: "magical", min: min, max: max, damage_type: type}, damage_percent ->
          ability_damage = Enum.random(min..max)

          resist = Mobile.magical_resistance_at_level(target, target_level)

          resist_percent = 1 - resist / (5 * 50 + resist)

          damage = ability_damage * resist_percent

          modifier = Mobile.ability_value(target, "Resist#{type}")

          damage = damage * (1 - modifier / 100)

          percent = damage / Mobile.max_hp_at_level(target, target_level)

          damage_percent + percent
      end)

    effects
    |> Map.put("Damage", damage_percent)
    |> Map.put("Interval", 1000)
    |> Map.put(
      "NextEffectAt",
      System.monotonic_time(:millisecond) + 1000
    )
  end

  def process_duration_trait({"Heal", value}, effects, target, caster, ability, _room) do
    roll = Enum.random(value["min"]..value["max"])

    attribute_value = Mobile.spellcasting_at_level(caster, caster.level, ability)

    modifier = (attribute_value + 50) / 100

    healing = roll * modifier

    percentage_healed = healing / Mobile.max_hp_at_level(target, target.level)

    effects
    |> Map.put("Heal", percentage_healed)
    |> Map.put("Interval", Mobile.round_length_in_ms(caster) / 4)
    |> Map.put(
      "NextEffectAt",
      System.monotonic_time(:millisecond) + Mobile.round_length_in_ms(caster) / 4
    )
  end

  def process_duration_trait({"HealMana", value}, effects, target, caster, _ability, _room) do
    level = min(target.level, caster.level)
    healing = Mobile.magical_damage_at_level(caster, level) * (value / 100)

    percentage_healed =
      calculate_healing(healing, value) / Mobile.max_mana_at_level(target, level)

    effects
    |> Map.put("HealMana", percentage_healed)
    |> Map.put("Interval", Mobile.round_length_in_ms(caster) / 4)
    |> Map.put(
      "NextEffectAt",
      System.monotonic_time(:millisecond) + Mobile.round_length_in_ms(caster) / 4
    )
  end

  def process_duration_trait({trait, value}, effects, _target, _caster, _ability, _room) do
    put_in(effects[trait], value)
  end

  def affects_target?(%{} = target, %Ability{} = ability) do
    cond do
      Ability.has_ability?(ability, "AffectsLiving") and Mobile.has_ability?(target, "NonLiving") ->
        false

      Ability.has_ability?(ability, "AffectsAnimals") and !Mobile.has_ability?(target, "Animal") ->
        false

      Ability.has_ability?(ability, "AffectsUndead") and !Mobile.has_ability?(target, "Undead") ->
        false

      Ability.has_ability?(ability, "Poison") and Mobile.has_ability?(target, "PoisonImmunity") ->
        false

      true ->
        true
    end
  end

  def has_ability?(%Ability{} = ability, ability_name) do
    ability.traits
    |> Map.keys()
    |> Enum.member?(ability_name)
  end

  def apply_cooldowns(caster, %Ability{} = ability) do
    caster
    |> apply_ability_cooldown(ability)
  end

  def apply_ability_cooldown(caster, %Ability{cooldown: nil}), do: caster

  def apply_ability_cooldown(caster, %Ability{cooldown: cooldown, name: name}) do
    Systems.Effect.add(
      caster,
      %{
        "cooldown" => name,
        "RemoveMessage" => "#{Text.capitalize_first(name)} is ready for use again."
      },
      cooldown
    )
  end

  def caster_cast_message(
        %Ability{result: :dodged} = ability,
        %{} = _caster,
        %{} = target,
        _mobile
      ) do
    message =
      ability.traits["DodgeUserMessage"]
      |> Text.interpolate(%{"target" => target, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{result: :blocked} = _ability,
        %{} = _caster,
        %{} = target,
        _mobile
      ) do
    shield = Character.shield(target).name

    message =
      "{{target}} blocks your attack with {{target:his/her/their}} #{shield}!"
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{result: :parried} = _ability,
        %{} = _caster,
        %{} = target,
        _mobile
      ) do
    weapon = Character.weapon(target).name

    message =
      "{{target}} parries your attack with {{target:his/her/their}} #{weapon}!"
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{result: :resisted} = ability,
        %{} = _caster,
        %{} = target,
        _mobile
      ) do
    message =
      @resist_message.user
      |> Text.interpolate(%{"target" => target, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{result: :deflected} = _ability,
        %{} = _caster,
        %{} = target,
        _mobile
      ) do
    message =
      @deflect_message.user
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-red'>#{message}</span></p>"
  end

  def caster_cast_message(%Ability{} = ability, %{} = _caster, %Item{} = target, _mobile) do
    message =
      ability.user_message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{} = ability,
        %{} = _caster,
        %{ability_shift: nil} = target,
        _mobile
      ) do
    message =
      ability.user_message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
  end

  def caster_cast_message(
        %Ability{} = ability,
        %{} = caster,
        %{ability_shift: shift} = target,
        mobile
      ) do
    amount = -trunc(shift * Mobile.max_hp_at_level(target, mobile.level))

    cond do
      amount < 1 and has_ability?(ability, "Damage") ->
        if List.first(ability.traits["Damage"]).kind == "magical" do
          Map.put(ability, :result, :resisted)
        else
          Map.put(ability, :result, :deflected)
        end
        |> caster_cast_message(caster, target, mobile)

      :else ->
        message =
          ability.user_message
          |> Text.interpolate(%{"target" => target, "amount" => abs(amount)})
          |> Text.capitalize_first()

        "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
    end
  end

  def target_cast_message(
        %Ability{result: :dodged} = ability,
        %{} = caster,
        %{} = _target,
        _mobile
      ) do
    message =
      ability.traits["DodgeTargetMessage"]
      |> Text.interpolate(%{"user" => caster, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{result: :blocked} = _ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    shield = Character.shield(target).name

    message =
      "You block {{user}}'s attack with your #{shield}!"
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{result: :parried} = _ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    weapon = Character.weapon(target).name

    message =
      "You parry {{user}}'s attack with your #{weapon}!"
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{result: :resisted} = ability,
        %{} = caster,
        %{} = _target,
        _mobile
      ) do
    message =
      @resist_message.target
      |> Text.interpolate(%{"user" => caster, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{result: :deflected} = _ability,
        %{} = caster,
        %{} = _target,
        _mobile
      ) do
    message =
      @deflect_message.target
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first()

    "<p><span class='dark-red'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{} = ability,
        %{} = caster,
        %{ability_shift: nil} = _target,
        _mobile
      ) do
    message =
      ability.target_message
      |> Text.interpolate(%{"user" => caster})
      |> Text.capitalize_first()

    "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
  end

  def target_cast_message(
        %Ability{} = ability,
        %{} = caster,
        %{ability_shift: _shift} = target,
        mobile
      ) do
    amount = -trunc(target.ability_shift * Mobile.max_hp_at_level(target, mobile.level))

    cond do
      amount < 1 and has_ability?(ability, "Damage") ->
        if List.first(ability.traits["Damage"]).kind == "magical" do
          Map.put(ability, :result, :resisted)
        else
          Map.put(ability, :result, :deflected)
        end
        |> target_cast_message(caster, target, mobile)

      :else ->
        message =
          ability.target_message
          |> Text.interpolate(%{"user" => caster, "amount" => abs(amount)})
          |> Text.capitalize_first()

        "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
    end
  end

  def spectator_cast_message(
        %Ability{result: :dodged} = ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    message =
      ability.traits["DodgeSpectatorMessage"]
      |> Text.interpolate(%{"user" => caster, "target" => target, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{result: :blocked} = _ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    shield = Character.shield(target).name

    message =
      "{{target}} blocks {{user}}'s attack with {{target:his/her/their}} #{shield}!"
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{result: :parried} = _ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    weapon = Character.weapon(target).name

    message =
      "{{target}} parries {{user}}'s attack with {{target:his/her/their}} #{weapon}!"
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{result: :resisted} = ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    message =
      @resist_message.spectator
      |> Text.interpolate(%{"user" => caster, "target" => target, "ability" => ability.name})
      |> Text.capitalize_first()

    "<p><span class='dark-cyan'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{result: :deflected} = _ability,
        %{} = caster,
        %{} = target,
        _mobile
      ) do
    message =
      @deflect_message.spectator
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    "<p><span class='dark-red'>#{message}</span></p>"
  end

  def spectator_cast_message(%Ability{} = ability, %{} = caster, %Item{} = target, _mobile) do
    message =
      ability.spectator_message
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{} = ability,
        %{} = caster,
        %{ability_shift: nil} = target,
        _mobile
      ) do
    message =
      ability.spectator_message
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
  end

  def spectator_cast_message(
        %Ability{} = ability,
        %{} = caster,
        %{ability_shift: _shift} = target,
        mobile
      ) do
    amount = -trunc(target.ability_shift * Mobile.max_hp_at_level(target, mobile.level))

    cond do
      amount < 1 and has_ability?(ability, "Damage") ->
        if List.first(ability.traits["Damage"]).kind == "magical" do
          Map.put(ability, :result, :resisted)
        else
          Map.put(ability, :result, :deflected)
        end
        |> spectator_cast_message(caster, target, mobile)

      :else ->
        message =
          ability.spectator_message
          |> Text.interpolate(%{"user" => caster, "target" => target, "amount" => abs(amount)})
          |> Text.capitalize_first()

        "<p><span class='#{message_color(ability)}'>#{message}</span></p>"
    end
  end

  def display_cast_message(%Room{} = room, %{} = caster, %Item{} = target, %Ability{} = ability) do
    room.mobiles
    |> Map.values()
    |> Enum.each(fn mobile ->
      cond do
        mobile.ref == caster.ref and not is_nil(ability.user_message) ->
          Mobile.send_scroll(mobile, caster_cast_message(ability, caster, target, mobile))

        mobile && not is_nil(ability.spectator_message) ->
          Mobile.send_scroll(mobile, spectator_cast_message(ability, caster, target, mobile))

        true ->
          :noop
      end
    end)
  end

  def display_cast_message(%Room{} = room, %{} = caster, %{} = target, %Ability{} = ability) do
    room.mobiles
    |> Map.values()
    |> Enum.each(fn mobile ->
      cond do
        mobile.ref == caster.ref and not is_nil(ability.user_message) ->
          Mobile.send_scroll(mobile, caster_cast_message(ability, caster, target, mobile))

        mobile.ref == target.ref and not is_nil(ability.target_message) ->
          Mobile.send_scroll(mobile, target_cast_message(ability, caster, target, mobile))

        mobile && not is_nil(ability.spectator_message) ->
          Mobile.send_scroll(mobile, spectator_cast_message(ability, caster, target, mobile))

        true ->
          :noop
      end
    end)
  end

  def display_pre_cast_message(
        %Room{} = room,
        %{} = caster,
        [target_ref | _rest] = targets,
        %Ability{traits: %{"PreCastMessage" => message}} = ability
      ) do
    target = Room.get_mobile(room, target_ref)

    message =
      message
      |> Text.interpolate(%{"target" => target})
      |> Text.capitalize_first()

    Mobile.send_scroll(caster, "<p><span class='#{message_color(ability)}'>#{message}</span></p>")

    display_pre_cast_message(
      room,
      caster,
      targets,
      update_in(ability.traits, &Map.delete(&1, "PreCastMessage"))
    )
  end

  def display_pre_cast_message(
        %Room{} = room,
        %{} = caster,
        [target_ref | _rest],
        %Ability{traits: %{"PreCastSpectatorMessage" => message}} = ability
      ) do
    target = Room.get_mobile(room, target_ref)

    message =
      message
      |> Text.interpolate(%{"user" => caster, "target" => target})
      |> Text.capitalize_first()

    Room.send_scroll(room, "<p><span class='#{message_color(ability)}'>#{message}</span></p>", [
      caster
    ])
  end

  def display_pre_cast_message(_room, _caster, _targets, _ability), do: :noop

  def message_color(%Ability{kind: kind}) when kind in ["attack", "critical"], do: "red"
  def message_color(%Ability{}), do: "blue"

  def can_execute?(%Room{} = room, mobile, ability) do
    cond do
      cd = on_cooldown?(mobile, ability) ->
        Mobile.send_scroll(
          mobile,
          "<p>#{ability.name} is on cooldown: #{time_remaining(mobile, cd)} seconds remaining.</p>"
        )

        false

      Mobile.confused(mobile, room) ->
        false

      Mobile.silenced(mobile, room) ->
        false

      not_enough_mana?(mobile, ability) ->
        false

      true ->
        true
    end
  end

  def time_remaining(mobile, cd) do
    timer =
      cd
      |> Map.get("timers")
      |> Enum.at(0)

    time = TimerManager.time_remaining(mobile, timer)
    Float.round(time / 1000, 2)
  end

  def on_cooldown?(%{} = _mobile, %Ability{cooldown: nil} = _ability), do: false

  def on_cooldown?(%{effects: effects} = _mobile, %Ability{name: name} = _ability) do
    effects
    |> Map.values()
    |> Enum.any?(&(&1["cooldown"] == name))
  end

  def get_targets(%Room{} = room, caster_ref, %Ability{targets: "monster or single"}, query) do
    caster = room.mobiles[caster_ref]

    match =
      room.mobiles
      |> Map.values()
      |> Enum.reject(&(&1.ref in Party.refs(room, caster)))
      |> Enum.reject(
        &(&1.sneaking && !(&1.ref in caster.detected_characters) && !(&1.ref == caster_ref))
      )
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end

  def get_targets(%Room{}, _caster_ref, %Ability{targets: "self"}, _query) do
    []
  end

  def get_targets(%Room{} = room, _caster_ref, %Ability{targets: "monster"}, query) do
    match =
      room.mobiles
      |> Map.values()
      |> Enum.filter(&(&1.__struct__ == Monster))
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end

  def get_targets(%Room{} = room, caster_ref, %Ability{targets: "full party area"}, "") do
    room
    |> Room.get_mobile(caster_ref)
    |> Mobile.party_refs(room)
  end

  def get_targets(%Room{}, _caster_ref, %Ability{targets: "full party area"}, _query) do
    []
  end

  def get_targets(%Room{} = room, caster_ref, %Ability{targets: "full attack area"}, "") do
    party =
      room
      |> Room.get_mobile(caster_ref)
      |> Mobile.party_refs(room)

    room.mobiles
    |> Map.keys()
    |> Kernel.--(party)
  end

  def get_targets(%Room{}, _caster_ref, %Ability{targets: "full attack area"}, _query) do
    []
  end

  def get_targets(%Room{}, _caster_ref, %Ability{targets: "self or single"}, "") do
    []
  end

  def get_targets(%Room{} = room, caster_ref, %Ability{targets: "self or single"}, query) do
    caster = room.mobiles[caster_ref]

    match =
      room.mobiles
      |> Map.values()
      |> Enum.reject(&(&1.__struct__ == Monster))
      |> Enum.reject(
        &(&1.sneaking && !(&1.ref in caster.detected_characters) && !(&1.ref == caster_ref))
      )
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end

  def get_targets(%Room{} = room, caster_ref, %Ability{targets: "single"}, query) do
    caster = room.mobiles[caster_ref]

    match =
      room.mobiles
      |> Map.values()
      |> Enum.reject(&(&1.__struct__ == Monster || &1.ref == caster_ref))
      |> Enum.reject(&(&1.sneaking && !(&1.ref in caster.detected_characters)))
      |> Match.one(:name_contains, query)

    List.wrap(match && match.ref)
  end

  def item_target(room, caster_ref, query) do
    %Character{inventory: inventory} = room.mobiles[caster_ref]

    item = Match.one(inventory, :keyword_starts_with, query)

    case item do
      nil ->
        nil

      %Item{} = item ->
        item
    end
  end

  def not_enough_mana?(%{} = _mobile, %Ability{ignores_round_cooldown?: true}), do: false

  def not_enough_mana?(%{} = mobile, %Ability{} = ability) do
    if !Mobile.enough_mana_for_ability?(mobile, ability) do
      Mobile.send_scroll(
        mobile,
        "<p><span class='cyan'>You do not have enough mana to use that ability.</span></p>"
      )
    end
  end
end
