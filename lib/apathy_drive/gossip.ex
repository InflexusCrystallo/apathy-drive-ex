defmodule ApathyDrive.Gossip do
  use GenServer
  alias ApathyDrive.Gossip.Socket
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, %{socket: nil, channels: []}, name: __MODULE__)
  end

  def update_channel_subscriptions(channels) do
    GenServer.call(__MODULE__, {:update_channel_subscriptions, channels})
  end

  def broadcast(channel, character_name, message) do
    GenServer.call(__MODULE__, {:broadcast, channel, character_name, message})
  end

  def receive_message(payload) do
    GenServer.call(__MODULE__, {:receive_message, payload})
  end

  def respond_to_heartbeat do
    GenServer.call(__MODULE__, :respond_to_heartbeat)
  end

  def init(state) do
    if config(:enabled), do: send(self(), :connect)
    {:ok, state}
  end

  def handle_call({:broadcast, channel, character_name, message}, _from, state) do
    if channel in state.channels do
      Logger.debug(
        "Gossip broadcast message to #{inspect(state.socket)} channel #{channel} for player #{
          character_name
        }: #{message}"
      )

      WebSockex.cast(state.socket, {:broadcast, channel, character_name, message})
      {:reply, :ok, state}
    else
      Logger.debug(
        "Gossip attempted to broadcast message for channel #{channel} but is only subscribed to #{
          inspect(state.channels)
        }"
      )

      {:reply, :ok, state}
    end
  end

  def handle_call({:receive_message, payload}, _from, state) do
    Logger.debug("Gossip received message: #{inspect(payload)}")

    ApathyDriveWeb.Endpoint.broadcast!("chat:#{payload["channel"]}", "scroll", %{
      html:
        "<p>[<span class='dark-magenta'>gossip</span> : #{
          ApathyDrive.Character.sanitize(payload["name"])
        }@#{ApathyDrive.Character.sanitize(payload["game"])}] #{
          ApathyDrive.Character.sanitize(payload["message"])
        }</p>"
    })

    {:reply, :ok, state}
  end

  def handle_call(:respond_to_heartbeat, _from, state) do
    response =
      Poison.encode!(%{
        event: "heartbeat",
        payload: %{players: ApathyDrive.Commands.Who.names()}
      })

    Logger.info("Gossip responding to heartbeat with #{inspect(response)}")

    {:reply, {:ok, response}, state}
  end

  def handle_call({:update_channel_subscriptions, channels}, _from, state) do
    state = %{state | channels: channels}
    Logger.debug("Updated channel subscriptions: #{inspect(state.channels)}")
    {:reply, :ok, state}
  end

  def handle_info(:connect, state) do
    case Socket.start_link() do
      {:ok, socket} ->
        {:noreply, %{state | socket: socket}}

      {:error, error} ->
        Logger.error(
          "failed to connect to Gossip server, retrying in 5 seconds: #{inspect(error)}"
        )

        Process.send_after(self(), :connect, 5000)
        {:noreply, state}
    end
  end

  defp config(key) do
    Application.get_all_env(:apathy_drive)[:gossip][key]
  end
end
