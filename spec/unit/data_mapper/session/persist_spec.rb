require 'spec_helper'

describe DataMapper::Session, '#persist' do
  subject { object.persist(domain_object) }

  let(:mapper)        { registry.resolve_model(Spec::DomainObject)              }
  let(:registry)      { Spec::Registry.new                                      }
  let(:domain_object) { Spec::DomainObject.new                                  }
  let(:object)        { described_class.new(registry)                           }
  let(:mapping)       { DataMapper::Session::Mapping.new(mapper, domain_object) }
  let(:old_tuple)     { mapping.tuple                                           }
  let(:identity)      { :a                                                      }

  context 'with untracked domain object' do
    it 'should insert update' do
      subject
      mapper.inserts.should == [mapping]
    end

    it_should_behave_like 'a command method'
    it_should_behave_like 'an operation that dumps once'

  end

  context 'with tracked domain object' do
    before do
      object.persist(domain_object)
    end

    shared_examples_for 'an update' do
      let(:modified_tuple) do
        { :key_attribute => :a, :other_attribute => :dirty }
      end

      let(:old_state) do
        mock('State', :tuple => old_tuple)
      end

      let(:state) do
        mock('State', :object => domain_object, :identity => :a, :tuple => modified_tuple, :old => old_state)
      end

      it 'should should update domain object' do
        subject
        mapper.updates.should eql([DataMapper::Session::Operand::Update.new(state)])
      end

      it_should_behave_like 'a command method'
      it_should_behave_like 'an operation that dumps once'

    end

    # This is a differend test case than the attribute change. 
    # We have to make sure we cache the loaded dump and compare this to 
    # future dumps without storing a dump of an object we just loaded.
    context 'and object is dirty from tuple generation change' do

      before do
        new_dumper = mock('Dump', :identity => identity, :tuple => modified_tuple)
        mapper.stub(:dumper => new_dumper)
      end

      it_should_behave_like 'an update'
    end

    context 'and object is dirty from attribute change' do


      before do
        domain_object.other_attribute = :dirty
      end

      it_should_behave_like 'an update'

    end

    context 'and object is NOT dirty' do
      it 'should not update' do
        subject
        mapper.updates.should == []
      end

      it_should_behave_like 'a command method'
      it_should_behave_like 'an operation that dumps once'

    end
  end
end
