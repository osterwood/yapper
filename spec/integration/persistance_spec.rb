describe 'Nanoid persisting documents' do
  before do
    class Document
      include Nanoid::Document

      field :field_1
      field :field_2
    end
  end
  after { Nanoid::DB.purge }

  it 'can batch updates for better performance on CUD' do
    Document.batch(10) do
      3.times { Document.create(:field_1 => 'saved') }

      Document.where(:field_1 => 'saved').count.should == 0
    end
    Document.where(:field_1 => 'saved').count.should == 3
  end

  describe 'creating documents' do
    it 'does not support hashes' do
      #NOTE: Due to a bug with sorting documents including hash fields
      lambda {
        Document.create(:field_1 => { :a => 'a' })
      }.should.raise(ArgumentError)
    end

    describe "when using #new then #save" do
      it 'persists the fields' do
        doc = Document.new
        doc.field_1 = 'field1'
        doc.field_2 = 'field2'
        doc.new_record?.should == true
        doc.save

        doc = Document.find(doc.id)
        doc.new_record?.should == false
        doc.field_1.should == 'field1'
        doc.field_2.should == 'field2'
      end
    end

    describe "when using #create" do
      it 'persists the fields' do
        doc = Document.create(:field_1 => 'field1',
                              :field_2 => 'field2')

        doc = Document.find(doc.id)
        doc.field_1.should == 'field1'
        doc.field_2.should == 'field2'
      end
    end
  end

  describe 'updating documents' do
    before do
      @doc = Document.create(:field_1 => 'field1')
    end

    describe "when updating fields and then #save" do
      it 'persists the fields' do
        @doc.field_1 = 'field1_updated'
        @doc.save

        doc = Document.find(@doc.id)
        doc.field_1.should == 'field1_updated'
      end
    end

    describe "when using #update_attributes" do
      it 'persists the fields' do
        @doc.update_attributes(:field_1 => 'field1_updated')

        doc = Document.find(@doc.id)
        doc.field_1.should == 'field1_updated'
      end
    end
  end
end
