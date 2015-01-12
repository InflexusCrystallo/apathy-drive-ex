defmodule Systems.Room do
  use Systems.Reload
  import Utility

  def display_room_in_scroll(spirit, monster, room_pid) do
    send_message(spirit, "scroll", long_room_html(spirit, monster, room_pid))
  end

  def long_room_html(spirit, nil, room) do
    directions = room |> exit_directions |> exit_directions_html
    "<div class='room'>#{name_html(room)}#{description_html(room)}#{shop(room)}#{items_html(room)}#{entities_html(spirit, room)}#{directions}</div>"
  end

  def long_room_html(spirit, monster, room) do
    light = light_level(room, monster)
    if light > -200 and light < 200 do
      directions = room |> exit_directions |> exit_directions_html
      "<div class='room'>#{name_html(room)}#{description_html(room)}#{shop(room)}#{items_html(room)}#{entities_html(monster, room)}#{directions}#{light(room, monster)}</div>"
    else
      "<div class='room'>#{light(room, monster)}</div>"
    end
  end

  def short_room_html(character, room) do
    if light_level(room, character) > -200 do
      directions = room |> exit_directions |> exit_directions_html
      "<div class='room'>#{name_html(room)}#{directions}</div>"
    else
      "<div class='room'>#{light(room, character)}</div>"
    end
  end

  def shop(room) do
    if Room.shop?(room) or Room.trainer?(room) do
      "<p><br><em>Type 'list' to see a list of goods and services sold here.</em><br><br></p>"
    else
      ""
    end
  end

  def get_current_room(entity) do
    Parent.of(entity)
  end

  def exit_directions(room) do
    exits(room)
    |> Enum.map(fn(room_exit) ->
         :"Elixir.Systems.Exits.#{room_exit.kind}".display_direction(room, room_exit)
       end)
    |> Enum.reject(&(&1 == nil))
  end

  def exit_directions_html([]) do
    "<div class='exits'>Obvious exits: NONE</div>"
  end

  def exit_directions_html(directions) do
    "<div class='exits'>Obvious exits: #{Enum.join(directions, ", ")}</div>"
  end

  def exits(room) do
    Room.value(room).exits
  end

  def description(room) do
    Room.value(room).description
  end

  def description_html(room) do
    "<div class='description'>#{description(room)}</div>"
  end

  def name(room) do
    Room.value(room).name
  end

  def name_html(room) do
    "<div class='title'>#{name(room)}</div>"
  end

  def items(room) do
    Room.value(room).items |> Enum.map(&Systems.Item.item_name/1)
  end

  def items_html(room) do
    items = items(room)

    case Enum.count(items) do
      0 ->
        ""
      _ ->
        "<div class='items'>You notice #{Enum.join(items(room), ", ")} here.</div>"
    end
  end

  def light(light_level)  when light_level < -1000, do: "<p>You are blind.</p>"
  def light(light_level)  when light_level <= -300, do: "<p>The room is pitch black - you can't see anything</p>"
  def light(light_level)  when light_level <= -200, do: "<p>The room is very dark - you can't see anything</p>"
  def light(light_level)  when light_level <= -100, do: "<p>The room is barely visible</p>"
  def light(light_level)  when light_level <=  -25, do: "<p>The room is dimly lit</p>"
  def light(light_level)  when light_level >=  300, do: "<p>The room is blindingly bright - you can't see anything</p>"
  def light(light_level)  when light_level >=  200, do: "<p>The room is painfully bright - you can't see anything</p>"
  def light(light_level)  when light_level >=  100, do: "<p>The room is dazzlingly bright</p>"
  def light(light_level)  when light_level >=   25, do: "<p>The room is brightly lit</p>"
  def light(light_level), do: nil

  def light(room, monster) do
    light_level(room, monster)
    |> light
  end

  def light_level(nil, monster), do: 0
  def light_level(room, monster) do
    alignment = Components.Alignment.value(monster)
    light     = Room.value(room).light + light_in_room(room) + light_on_monsters(room)

    cond do
      alignment > 0 and light < 0 ->
        min(0, light + alignment)
      alignment < 0 and light > 0 ->
        max(0, light + alignment)
      true ->
        light
    end
    
  end

  def lights(items) do
    items
    |> Enum.filter(&(Entity.has_component?(&1, Components.Effects)))
    |> Enum.map(fn(item) ->
         item
         |> Components.Effects.lights
         |> Enum.sum
       end)
    |> Enum.sum
  end

  def light_in_room(room) do
    Room.value(room).items
    |> lights
  end

  def light_on_monsters(room) do
    room
    |> Systems.Room.living_in_room
    |> Enum.map(fn(monster) ->
         Systems.Limbs.equipped_items(monster) ++ Components.Items.get_items(monster)
       end)
    |> List.flatten
    |> lights
  end

  def entities(entity, room) do
    monsters_in_room(room) |> Enum.reject(&(entity == &1))
  end

  def entities_html(character, room) do
    entities = entities(character, room)
    case Enum.count(entities) do
      0 ->
        ""
      _ ->
        entities = entities
                   |> Enum.map(fn(entity) ->
                        cond do
                          Components.Alignment.evil?(entity) ->
                            "<span class='magenta'>#{Components.Name.value(entity)}</span>"
                          Components.Alignment.good?(entity) ->
                            "<span class='grey'>#{Components.Name.value(entity)}</span>"
                          Components.Alignment.neutral?(entity) ->
                            "<span class='dark-cyan'>#{Components.Name.value(entity)}</span>"
                        end
                      end)
                   |> Enum.join("<span class='magenta'>, </span>")
        "<div class='entities'><span class='dark-magenta'>Also here:</span> #{entities}<span class='dark-magenta'>.</span></div>"
    end
  end

  def move(spirit, monster, direction) do
    Systems.Exit.move(spirit, monster, direction)
  end

  def living_in_room(room) do
    characters = characters_in_room(room) |> Enum.reject(&(Components.Spirit.value(&1)))
    Enum.concat(monsters_in_room(room), characters)
  end

  def living_in_room(entities, room) do
    Enum.filter(entities, &(room == Parent.of(&1)))
  end

  def characters_in_room(room) do
    Characters.online
    |> living_in_room(room)
  end

  def monsters_in_room(room) do
    Room.value(room).monsters
  end

  def characters_in_room(room, character_to_exclude) do
    characters_in_room(room) |> Enum.reject(&(&1 == character_to_exclude))
  end

end
