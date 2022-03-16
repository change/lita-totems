require 'signalfx'

module Stats
  module_function
  SIGNALFX_TOTEMS_METRICS_DASHBOARD = "https://app.signalfx.com/#/dashboard/FNSkEUVAYAA"

  def signalfx_client
    @signalfx_client ||= SignalFx.new ENV['LITA_SIGNALFX_TOKEN']
  end

  def send_gauges_to_signalFX(metric, value)
    signalfx_client.send( 
      gauges:
        [ 
          {  
          :metric => metric,
          :value => value,
          :timestamp => (Time.now.to_f * 1000).to_i
        }
      ]
    )
  end

  def send_counter_to_signalFX(metric, value)
    signalfx_client.send( 
      counters:
        [ 
          {  
          :metric => metric,
          :value => value,
          :timestamp => (Time.now.to_f * 1000).to_i
        }
      ]
    )
  end

  # captures how many times a totem has being added
  def capture_totem_use(totem)
    send_counter_to_signalFX("totems:add:#{totem}", 1)
  end

  # captures how many people are waiting for a totem.
  def capture_people_waiting(totem,queue_size)
    send_gauges_to_signalFX("totems:people_waiting:#{totem}", queue_size)
  end

  # captures totem's holding time by user
  def capture_holding_time(totem, waiting_since_hash_user_id)
    user_holding_time_in_seconds = Time.now.to_i - waiting_since_hash_user_id.to_i
    user_holding_time_in_minutes = user_holding_time_in_seconds / 60
    send_gauges_to_signalFX("totems:holding_time:#{totem}",user_holding_time_in_minutes)
  end

  # captures totem's waiting time by the next user
  def capture_waiting_time(totem, waiting_since_hash_next_user_id)
    user_waiting_time_in_seconds = Time.now.to_i - waiting_since_hash_next_user_id.to_i
    user_holding_time_in_minutes = user_waiting_time_in_seconds / 60
    send_gauges_to_signalFX("totems:holding_time:#{totem}",user_holding_time_in_minutes)
  end

  def signalfx_dashboard
    SIGNALFX_TOTEMS_METRICS_DASHBOARD
  end

end