require "spec_helper"

describe Lita::Handlers::Totems, lita_handler: true do
  it { is_expected.to route("totems add foo").to(:add) }
  it { is_expected.to route("totem add foo").to(:add) }
  it { is_expected.to route("totem join foo").to(:add) }
  it { is_expected.to route("totems add foo message").to(:add) }
  it { is_expected.not_to route("totems add ").to(:add) }
  it { is_expected.not_to route("tote add foo").to(:add) }
  it { is_expected.to route("totems add chicken timeout: 10").to(:add) }
  it { is_expected.to route("totems add chicken timeout: 20").to(:add) }
  it { is_expected.to route("totems add chicken message timeout: 10").to(:add) }
  it { is_expected.to route("totems add chicken other message timeout:20").to(:add) }
  it { is_expected.to route("totems kick foo").to(:kick) }
  it { is_expected.to route("totems kick foo bob").to(:kick) }
  it { is_expected.to route("totems").to(:info) }
  it { is_expected.to route("totems info").to(:info) }
  it { is_expected.to route("totems info chicken").to(:info) }
  it { is_expected.to route("totems get stats").to(:stats) }

  # mock stats to not send test data to signalfx
  before(:each) do
    signalfx_client = double("Stats").as_null_object
    allow(Stats).to receive(:send_counter_to_signalFX).and_return(signalfx_client)
    allow(Stats).to receive(:send_gauges_to_signalFX).and_return(signalfx_client)
  end

  let(:totem_creator) { Class.new do
    def initialize
      @id = 0
    end

    def create(container)
      @id  += 1
      name = "totem_#{@id}"
      container.send_message("totems create #{name}")
      name
    end
  end.new
  }

  let(:carl) { Lita::User.create(123, name: "Carl") }
  let(:user_generator) { Class.new do
    def initialize
      @id = 0
    end

    def generate
      @id += 1
      Lita::User.create(@id, name: "person_#{@id}")
    end
  end.new
  }
  let(:another_user) { user_generator.generate }
  let(:yet_another_user) { user_generator.generate }

  describe "get stats" do
    it "returns signalfx metric dashboard link" do
      send_message('totems get stats')
      expect(replies.last).to eq('https://app.signalfx.com/#/dashboard/FNSkEUVAYAA')
    end
  end

  describe "create" do
    it "creates a totem" do
      send_message('totems create chicken')
      expect(replies.last).to eq('Created totem "chicken".')

      send_message('totems create chicken')
      expect(replies.last).to eq('Error: totem "chicken" already exists.')
    end
  end

  describe "destroy" do
    def send_destroy_message
      send_message('totems destroy chicken')
    end

    context "totem is present" do
      before do
        send_message('totems create chicken')
      end

      it "kicks successfully" do
        send_destroy_message
        expect(replies.last).to eq('Destroyed totem "chicken".')
      end

    end
    context "totem isn't present" do
      it "kicks unsuccessfully" do
        send_destroy_message
        expect(replies.last).to eq(%{Error: totem "chicken" doesn't exist.})
      end

    end

  end

  describe "add" do

    context "totem exists" do
      before do
        send_message("totems create chicken")
        send_message("totems create noir")
      end

      context "when nobody is in line" do
        it "gives totem to the user" do
          send_message("totems add chicken", as: carl)
          expect(replies.last).to eq('Carl, you now have totem "chicken".')
        end

        it "calls capture_totem_use with the specified totem" do
          expect(Stats).to receive(:capture_totem_use).with("chicken")
          send_message("totems add chicken", as: carl)
        end
      end

      context "when someone holds the totem" do
        before do
          send_message("totems add chicken", as: another_user)
        end

        it "notifies the owner when somebody just added the specified totem" do
          expect(robot).to receive(:send_messages).twice do |target, message|
            expect([another_user.id, carl.id]).to include(target.user.id)
            if target.user.id == another_user.id
              expect(message).to eq(%{#{carl.name} just added the "chicken" totem, are you still using it?})
            elsif target.user.id == carl.id
              expect(message).to eq(%{Carl, you are #1 in line for totem "chicken".})
            end
          end
          send_message("totems add chicken", as: carl)
        end

        it "doesnt notify the owner when another person added the specified totem" do
          expect(robot).to receive(:send_messages).thrice do |target, message|
            expect([another_user.id, carl.id, yet_another_user.id]).to include(target.user.id)
            if target.user.id == another_user.id
              expect(message).to eq(%{#{carl.name} just added the "chicken" totem, are you still using it?})
              expect(message).not_to eq(%{#{yet_another_user.name} just added the "chicken" totem, are you still using it?})
            elsif target.user.id == carl.id
              expect(message).to eq(%{Carl, you are #1 in line for totem "chicken".})
            elsif target.user.id == yet_another_user.id
              expect(message).to eq(%{#{yet_another_user.name}, you are #2 in line for totem "chicken".})
            end
          end
          send_message("totems add chicken", as: carl)
          send_message("totems add chicken", as: yet_another_user)
        end
      end

      context "when people are in line" do
        before do
          send_message("totems add chicken", as: user_generator.generate)
          send_message("totems add chicken", as: user_generator.generate)
        end
        it "adds user to the queue" do
          send_message("totems add chicken", as: carl)
          expect(replies.last).to eq('Carl, you are #2 in line for totem "chicken".')
        end

        it "calls capture_totem_use with the specified totem" do
          expect(Stats).to receive(:capture_totem_use).with("chicken")
          send_message("totems add chicken", as: carl)
        end

        it "calls capture_people_waiting with the specified totem and queue size" do
          expect(Stats).to receive(:capture_people_waiting).with("chicken", 2)
          send_message("totems add chicken", as: carl)
        end

      end
      context "when the user is already holding the totem" do
        before do
          send_message("totems add chicken", as: carl)
        end
        it "returns an error message" do
          send_message("totems add chicken", as: carl)
          expect(replies.last).to eq('Error: you already have the totem "chicken".')
        end

        it "doesnt call capture_totem_use with the specified totem" do
          expect(Stats).not_to receive(:capture_totem_use).with("chicken")
          send_message("totems add chicken", as: carl)
        end

      end

      context "when the user is already in line for the totem" do
        before do
          send_message("totems add chicken", as: another_user)
          send_message("totems add chicken", as: carl)
        end
        it "returns an error message" do
          send_message("totems add chicken", as: carl)
          expect(replies.last).to eq('Error: you are already in the queue for "chicken".')
        end

        it "doesnt call capture_totem_use with the specified totem" do
          expect(Stats).not_to receive(:capture_totem_use).with("chicken")
          send_message("totems add chicken", as: carl)
        end

      end

      context "when totems add multiple times" do
         it "calls capture_totem_use with the specified totem" do
          expect(Stats).to receive(:capture_totem_use).with("chicken").thrice
          send_message("totems add chicken message", as: carl)
          send_message("totems add chicken", as: another_user)
          send_message("totems add chicken other message", as: yet_another_user)
        end
      end

      context "with a timeout" do
        it "includes the timeout in the totems' info" do
          Timecop.freeze("2014-03-01 12:00:00") do
            send_message("totems add noir timeout: 10", as: carl)
            send_message("totems add noir", as: another_user)
            send_message("totems add noir timeout: 20", as: yet_another_user)
          end
          Timecop.freeze("2014-03-01 13:00:00") do
            send_message("totems info noir")
            expect(replies.last).to eq <<-END
*noir* *(#pd-contributor-demos)*
1. Carl (held for 1h) - timeout: 10
2. person_1 (waiting for 1h) - timeout: 24
3. person_2 (waiting for 1h) - timeout: 20
            END
          end
        end

        # These two tests require that the multiplication is removed from the timeout
        it "triggers the timeout when the totem is in the list" do
          send_message("totems add noir timeout: 3", as: carl)
          wait(10).for do
              send_message("totems info noir")
              replies.last
          end.to eq("*noir* *(#pd-contributor-demos)*\n1. Carl (held for 9s) - timeout: 3\n")
        end

        it "doesn't trigger timeout when the totem is not on a demo environment" do
          send_message("totems add chicken timeout: 3", as: carl)
          wait(5).for do
              send_message("totems info chicken")
              replies.last
          end.to eq("*chicken*\n1. Carl (held for 4s)\n")
        end
      end

      context "with a message" do
        before do
          Timecop.freeze("2014-03-01 12:00:00") do
            send_message("totems add chicken message", as: carl)
            send_message("totems add chicken", as: another_user)
            send_message("totems add chicken other message", as: yet_another_user)
          end
        end
        it "includes the message in the totems' info" do
          Timecop.freeze("2014-03-01 13:00:00") do
            send_message("totems info chicken")
            expect(replies.last).to eq <<-END
*chicken*
1. Carl (held for 1h) - message
2. person_1 (waiting for 1h)
3. person_2 (waiting for 1h) - other message
            END
          end
        end
      end

      context "with a message and a timeout" do
        before do
          Timecop.freeze("2014-03-01 12:00:00") do
            send_message("totems add noir message timeout: 10", as: carl)
            send_message("totems add noir", as: another_user)
            send_message("totems add noir other message timeout:20", as: yet_another_user)
          end
        end
        it "includes the timeout and the message in the totems' info" do
          Timecop.freeze("2014-03-01 13:00:00") do
            send_message("totems info noir")
            expect(replies.last).to eq <<-END
*noir* *(#pd-contributor-demos)*
1. Carl (held for 1h) - message - timeout: 10
2. person_1 (waiting for 1h) - timeout: 24
3. person_2 (waiting for 1h) - other message - timeout: 20
            END
          end
        end
      end
    end

    context "when the totem doesn't exist" do
      it "lets user know" do
        send_message("totems add chicken", as: carl)
        expect(replies.last).to eq('Error: there is no totem "chicken".')
      end

      it "doesnt call capture_totem_use with the specified totem" do
        expect(Stats).not_to receive(:capture_totem_use).with("chicken")
        send_message("totems add chicken message", as: carl)
      end
    end
  end

  describe "yield" do
    before do
      send_message("totems create chicken")
      send_message("totems create duck")
    end

    context "when user has one totem" do
      before do
        Timecop.freeze("2014-03-01 11:00:00") do
          send_message("totems add chicken", as: carl)
        end
      end

      it "calls capture_holding_time with the specified totem and user's holding time" do
        Timecop.freeze("2014-03-01 13:00:00") do
          expect(Stats).to receive(:capture_holding_time).with("chicken", "1393671600")
          send_message("totems yield chicken", as: carl)
        end
      end

      context "someone else is in line" do
        before do
          Timecop.freeze("2014-03-01 12:00:00") do
            send_message("totems add chicken", as: another_user)
            send_message("totems add chicken", as: yet_another_user)
          end
        end

        it "calls capture_waiting_time with the specified totem and next user waiting time" do
          Timecop.freeze("2014-03-01 13:00:00") do
            expect(Stats).to receive(:capture_waiting_time).with("chicken", "1393675200")
            send_message("totems yield chicken", as: carl)
          end
        end
 
        it "yields that totem, gives to the next person in line" do
          expect(robot).to receive(:send_messages).twice do |target, message|
            expect([another_user.id, carl.id]).to include(target.user.id)
            if target.user.id == another_user.id
              expect(message).to eq(%{You are now in possession of totem "chicken", yielded by #{carl.name}. There are 1 people in line after you.})
            elsif target.user.id == carl.id
              expect(message).to eq("You have yielded the totem to #{another_user.name}.")
            end
          end
          send_message("totems yield", as: carl)
        end
        it "updates the waiting since value for the new holder" do
          Timecop.freeze("2014-03-01 13:00:00") do
            send_message("totems info chicken")
            expect(replies.last).to eq <<-END
*chicken*
1. Carl (held for 2h)
2. person_1 (waiting for 1h)
3. person_2 (waiting for 1h)
            END
            send_message("totems yield", as: carl)
            send_message("totems info chicken")
            expect(replies.last).to eq <<-END
*chicken*
1. person_1 (held for 0s)
2. person_2 (waiting for 1h)
            END
          end
        end
      end
      context "nobody else is in line" do
        it "yields the totem and clears the owning_user_id" do
          send_message("totems yield", as: carl)
          expect(replies.last).to eq(%{You have yielded the "chicken" totem.})
          send_message("totems info chicken")
          expect(replies.last).to eq "*chicken* *- Available*\n"
        end

      end
    end
    context "when user has no totems" do
      it "sends an error" do
        send_message("totems yield", as: carl)
        expect(replies.last).to eq("Error: You do not have any totems to yield.")
      end
    end
    context "when user has multiple totems" do
      let(:other_totem) { totem_creator.create(self) }
      before do
        send_message("totems add chicken", as: carl)
        send_message("totems add #{other_totem}", as: carl)
      end
      context "when specifying a totem" do
        context "user doesn't have that totem" do
          it "sends error message" do
            send_message("totems yield duck", as: carl)
            expect(replies.last).to eq(%{Error: You don't own and aren't waiting for the "duck" totem.})
          end
        end
        context "user has that totem" do
          it "yields totem" do
            send_message("totems yield chicken", as: carl)
            expect(replies.last).to eq(%{You have yielded the "chicken" totem.})
          end

        end
      end
      context "when not specifying a totem" do
        it "sends a message about which totem it can yield" do
          send_message("totems yield", as: carl)
          expect(replies.last).to eq(%{You must specify a totem to yield.  Totems you own: ["chicken", "#{other_totem}"].  Totems you are in line for: [].})
        end
      end
    end
    context "when the user is in line for a single totem" do
      before do
        Timecop.freeze("2014-03-02 13:00:00") do
          send_message("totems add chicken", as: another_user)
          send_message("totems add chicken", as: carl)
        end
      end
      context "when specifying a totem" do
        context "user is not in line for that totem" do
          it "sends error message" do
            send_message("totems yield duck", as: carl)
            expect(replies.last).to eq(%{Error: You don't own and aren't waiting for the "duck" totem.})
          end
        end
        context "user is in line for that totem" do
          it "yields totem and does not update holder" do
            Timecop.freeze("2014-03-02 14:00:00") do
              send_message("totems yield chicken", as: carl)
              expect(replies.last).to eq(%{You are no longer in line for the "chicken" totem.})
              send_message("totems info chicken")
              expect(replies.last).to eq("*chicken*\n1. person_1 (held for 1h)\n")
            end
          end
        end
      end
      context "when not specifying a totem" do
        it "yields totem and does not update holder" do
          Timecop.freeze("2014-03-02 14:00:00") do
            send_message("totems yield", as: carl)
            expect(replies.last).to eq(%{You are no longer in line for the "chicken" totem.})
            send_message("totems info chicken")
            expect(replies.last).to eq("*chicken*\n1. person_1 (held for 1h)\n")
          end
        end
      end
    end

    context "when the user is in line for multiple totems" do
      before do
        Timecop.freeze("2014-03-02 13:00:00") do
          send_message("totems add chicken", as: another_user)
          send_message("totems add chicken", as: carl)
          send_message("totems add chicken", as: yet_another_user)
          send_message("totems add duck", as: yet_another_user)
          send_message("totems add duck", as: carl)
        end
      end
      context "when specifying a totem" do
        context "user is in line for that totem" do
          it "yields totem and does not update holder" do
            Timecop.freeze("2014-03-02 14:00:00") do
              send_message("totems yield chicken", as: carl)
              expect(replies.last).to eq(%{You are no longer in line for the "chicken" totem.})
              send_message("totems info chicken")
              expect(replies.last).to eq("*chicken*\n1. person_1 (held for 1h)\n2. person_2 (waiting for 1h)\n")
            end
          end
        end
      end
      context "when not specifying a totem" do
        it "sends error message" do
          Timecop.freeze("2014-03-02 14:00:00") do
            send_message("totems yield", as: carl)
            expect(replies.last).to eq(%{You must specify a totem to yield.  Totems you own: [].  Totems you are in line for: ["chicken", "duck"].})
          end
        end
      end
    end

    context "when the user is in line for a totem and has another totem" do
      before do
        Timecop.freeze("2014-03-02 13:00:00") do
          send_message("totems add chicken", as: another_user)
          send_message("totems add chicken", as: carl)
          send_message("totems add chicken", as: yet_another_user)
          send_message("totems add duck", as: carl)
          send_message("totems add duck", as: another_user)
        end
      end
      context "when specifying a totem" do
        context "user is in line for that totem" do
          it "yields totem and does not update holder" do
            Timecop.freeze("2014-03-02 14:00:00") do
              send_message("totems yield chicken", as: carl)
              expect(replies.last).to eq(%{You are no longer in line for the "chicken" totem.})
              send_message("totems info chicken")
              expect(replies.last).to eq("*chicken*\n1. person_1 (held for 1h)\n2. person_2 (waiting for 1h)\n")
            end
          end
        end
      end
      context "when not specifying a totem" do
        it "sends error message" do
          Timecop.freeze("2014-03-02 14:00:00") do
            send_message("totems yield", as: carl)
            expect(replies.last).to eq(%{You must specify a totem to yield.  Totems you own: ["duck"].  Totems you are in line for: ["chicken"].})
          end
        end
      end
    end
  end



  describe "kick" do
    before do
      send_message("totems create chicken")
    end
    context "there is a user owning the totem and somebody else waiting for it" do
      before do
        send_message("totems add chicken", as: another_user)
        send_message("totems add chicken", as: carl)
      end
      it "should notify that user that she has been kicked, and notify the next user she now has the totem" do
        expect(robot).to receive(:send_messages).twice do |target, message|
            expect([another_user.id, carl.id]).to include(target.user.id)
            if target.user.id == carl.id
              expect(message).to eq(%{You are now in possession of totem "chicken".})
            elsif target.user.id == another_user.id
              expect(message).to eq(%{You have been kicked from totem "chicken" by #{carl.name}.})
            end
          end
        send_message("totems kick chicken", as: carl)
      end
    end

    context "there is a user owning the totem" do
      before do
        send_message("totems add chicken", as: carl)
      end
      it "should notify that user that she has been kicked and clear the owning_user_id" do
        expect(robot).to receive(:send_messages).twice do |target, message|
          expect([another_user.id, carl.id]).to include(target.user.id)
          if target.user.id == carl.id
            expect(message).to eq(%{You have been kicked from totem "chicken" by #{user.name}.})
          elsif target.user.id == another_user.id
            expect(message).to eq("*chicken* *- Available*\n")
          end
        end
        send_message("totems kick chicken")
        send_message("totems info chicken")
      end
    end

    context "nobody owns that totem" do
      it "sends an error" do
        send_message("totems kick chicken")
        expect(replies.last).to eq(%{Error: Nobody owns totem "chicken" so you can't kick someone from it.})
      end
    end
  end

  describe "info" do
    before do
      Timecop.freeze("2014-03-01 12:00:00") do
        send_message("totems create chicken")
        send_message("totems create duck")
        send_message("totems create ball")
        send_message("totems add chicken", as: carl)
        send_message("totems add chicken", as: another_user)
        send_message("totems add chicken", as: yet_another_user)
        send_message("totems add duck", as: yet_another_user)
        send_message("totems add duck", as: carl)
      end
    end
    context "totem is passed" do
      it "shows info for just that totem" do
        Timecop.freeze("2014-03-01 13:00:00") do
          send_message("totems info chicken")
          expect(replies.last).to eq <<-END
*chicken*
1. Carl (held for 1h)
2. person_1 (waiting for 1h)
3. person_2 (waiting for 1h)
          END
        end
      end
    end

    context "totem isn't passed" do
      it "shows info for all totems" do
        Timecop.freeze("2014-03-02 13:00:00") do
          send_message("totems info")
          expect(replies.last).to include <<-END
*chicken*
  1. Carl (held for 1d 1h)
  2. person_1 (waiting for 1d 1h)
  3. person_2 (waiting for 1d 1h)

----------
          END
          expect(replies.last).to include <<-END
*duck*
  1. person_2 (held for 1d 1h)
  2. Carl (waiting for 1d 1h)

----------
          END
          expect(replies.last).to include <<-END
*ball* *- Available*

----------
          END
        end
      end
    end

  end

end
