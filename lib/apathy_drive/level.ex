defmodule ApathyDrive.Level do

  def exp_to_next_level(%Spirit{} = spirit) do
    exp_at_level(spirit.level + 1) - spirit.experience
  end

  def exp_for_level(1), do: 0
  def exp_for_level(lvl) do
    ((1 + :math.pow(lvl - 2, 1.50 + (lvl / 75.0))) * 100000 / 150)
    |> trunc
  end

  def exp_at_level(0), do: nil
  def exp_at_level(level) do
    (1..level)
    |> Enum.reduce(0, fn(lvl, total) ->
         total + exp_for_level(lvl)
       end)
  end

  def exp_reward(level) do
    needed = exp_at_level(level + 1) - exp_at_level(level)

    div(needed, 10 * level)
  end

  def level_at_exp(exp, level \\ 1) do
    if exp_at_level(level) > exp do
      level - 1
    else
      level_at_exp(exp, level + 1)
    end
  end

  def advance(%Spirit{} = spirit) do
    advance(spirit, exp_to_next_level(spirit))
  end

  def advance(%Spirit{} = spirit, exp_tnl) when exp_tnl < 1 do
    put_in(spirit.level, spirit.level + 1)
  end
  def advance(%Spirit{} = spirit, _exp_tnl), do: spirit

  def display_exp_table do
    Enum.each(1..50, fn(level) ->
      essence = String.rjust("#{exp_at_level(level)}", 8)
      essence_reward = String.rjust("#{exp_reward(level)}", 6)
      level = String.rjust("#{level}", 2)

      IO.puts "Level: #{level}, Essence Required: #{essence}, Essence per kill: #{essence_reward}"
    end)
  end

end