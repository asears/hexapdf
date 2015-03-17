# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/pdf/document'
require 'stringio'

describe HexaPDF::PDF::Document do

  before do
    @io = StringIO.new(<<EOF)
%PDF-1.7
1 0 obj
10
endobj

2 0 obj
20
endobj

xref
0 3
0000000000 65535 f 
0000000009 00000 n 
0000000028 00000 n 
trailer
<< /Size 3 >>
startxref
47
%%EOF

2 0 obj
200
endobj

xref
2 1
0000000158 00000 n 
trailer
<< /Size 3 /Prev 47 >>
startxref
178
%%EOF
EOF
    @io_doc = HexaPDF::PDF::Document.new(io: @io)
    @doc = HexaPDF::PDF::Document.new
  end

  describe "initialize" do
    it "doesn't need any arguments" do
      doc = HexaPDF::PDF::Document.new
      assert_equal('HexaPDF::PDF::Filter::ASCIIHexDecode', doc.config['filter.map'][:AHx])
    end

    it "takes a configuration hash as option" do
      doc = HexaPDF::PDF::Document.new(config: {'filter.map' => {AHx: 'Something'}})
      assert_equal('Something', doc.config['filter.map'][:AHx])
      assert_equal('HexaPDF::PDF::Filter::ASCII85Decode', doc.config['filter.map'][:A85])
    end

    it "takes an IO object as option" do
      doc = HexaPDF::PDF::Document.new(io: @io)
      assert_equal(10, doc.object(1).value)
    end
  end

  describe "object" do
    it "accepts a Reference object as argument" do
      assert_equal(10, @io_doc.object(HexaPDF::PDF::Reference.new(1, 0)).value)
    end

    it "accepts an object number as arguments" do
      assert_equal(10, @io_doc.object(1).value)
    end

    it "returns added objects" do
      obj = @io_doc.add(@io_doc.wrap({Type: :Test}, oid: 100))
      assert_equal(obj, @io_doc.object(100))
    end

    it "returns nil for unknown object references" do
      assert_nil(@io_doc.object(100))
    end

    it "returns only the newest version of an object" do
      assert_equal(200, @io_doc.object(2).value)
    end
  end

  describe "object?" do
    it "works with a Reference object as argument" do
      assert(@io_doc.object?(HexaPDF::PDF::Reference.new(1, 0)))
    end

    it "works with an object number as arguments" do
      assert(@io_doc.object?(1))
    end
  end

  describe "deref" do
    it "returns a dereferenced object when given a Reference object" do
      assert_equal(@io_doc.object(1), @io_doc.deref(HexaPDF::PDF::Reference.new(1, 0)))
    end

    it "returns the given object when it is not a Reference object" do
      assert_equal(5, @io_doc.deref(5))
    end
  end

  describe "add" do
    it "automatically assigns free object numbers" do
      assert_equal(1, @doc.add(5).oid)
      assert_equal(2, @doc.add(5).oid)
      assert_equal(3, @doc.add(5).oid)
    end

    it "assigns the object's document" do
      obj = @doc.add(5)
      assert_equal(@doc, obj.document)
    end

    it "allows adding a native ruby object" do
      obj = @doc.add(5)
      assert_equal(5, obj.value)
    end

    it "allows adding a HexaPDF::PDF::Object" do
      obj = @doc.add(HexaPDF::PDF::Object.new(5))
      assert_equal(5, obj.value)
    end

    it "returns the given object if it is already stored in the document" do
      obj = @doc.add(5)
      assert_same(obj, @doc.add(obj))
    end

    it "allows specifying a revision to which the object should be added" do
      @doc.revisions.add
      @doc.revisions.add

      @doc.add(@doc.wrap(5, oid: 1), revision: 0)
      assert_equal(5, @doc.object(1).value)

      @doc.add(@doc.wrap(10, oid: 1), revision: 2)
      assert_equal(10, @doc.object(1).value)

      @doc.add(@doc.wrap(7.5, oid: 1), revision: 1)
      assert_equal(10, @doc.object(1).value)
    end

    it "fails if the specified revision index is invalid" do
      assert_raises(HexaPDF::Error) { @doc.add(5, revision: 5) }
    end

    it "fails if the object to be added is associated with another document" do
      doc = HexaPDF::PDF::Document.new
      obj = doc.add(5)
      assert_raises(HexaPDF::Error) { @doc.add(obj) }
    end

    it "fails if the object number of the object to be added is already associated with another object" do
      obj = @doc.add(5)
      assert_raises(HexaPDF::Error) { @doc.add(@doc.wrap(5, oid: obj.oid, gen: 1)) }
    end
  end

  describe "delete" do
    it "works with a Reference object as argument" do
      obj = @doc.add(5)
      @doc.delete(obj, mark_as_free: false)
      refute(@doc.object?(obj))
    end

    it "works with an object number as arguments" do
      @doc.add(5)
      @doc.delete(1, mark_as_free: false)
      refute(@doc.object?(1))
    end

    describe "with an object in multiple revisions" do
      before do
        @ref = HexaPDF::PDF::Reference.new(2, 3)
        obj = @doc.wrap(5, oid: @ref.oid, gen: @ref.gen)
        @doc.revisions.add
        @doc.add(obj, revision: 0)
        @doc.add(obj, revision: 1)
      end

      it "deletes an object for all revisions when revision = :all" do
        @doc.delete(@ref, revision: :all, mark_as_free: false)
        refute(@doc.object?(@ref))
      end

      it "deletes an object only in the current revision when revision = :current" do
        @doc.delete(@ref, revision: :current, mark_as_free: false)
        assert(@doc.object?(@ref))
      end

      it "marks the object as PDF null object when using mark_as_free=true" do
        @doc.delete(@ref, revision: :current)
        assert(@doc.object(@ref).null?)
      end
    end

    it "fails if the revision argument is invalid" do
      assert_raises(HexaPDF::Error) { @doc.delete(1, revision: :invalid) }
    end
  end

  describe "wrap" do
    before do
      @myclass = Class.new(HexaPDF::PDF::Object)
      @myclass2 = Class.new(HexaPDF::PDF::Object)
      @doc.config['object.map'][[:MyClass, nil]] = @myclass
      @doc.config['object.map'][[:MyClass, :TheSecond]] = @myclass2
    end

    it "returns an object of type HexaPDF::PDF::Object" do
      assert_kind_of(HexaPDF::PDF::Object, @doc.wrap(5))
      assert_kind_of(HexaPDF::PDF::Object, @doc.wrap({}, stream: ''))
    end

    it "associates the returned object with the document" do
      assert_equal(@doc, @doc.wrap(5).document)
    end

    it "sets the given object (not === HexaPDF::PDF::Object) as value for the PDF object" do
      assert_equal(5, @doc.wrap(5).value)
    end

    it "uses the data of the given PDF object for re-wrapping" do
      obj = @doc.wrap({a: :b}, oid: 10, gen: 20, stream: 'hallo')
      new_obj = @doc.wrap(obj)
      assert_equal({a: :b}, new_obj.value)
      assert_equal('hallo', new_obj.raw_stream)
      assert_equal(10, new_obj.oid)
      assert_equal(20, new_obj.gen)
      refute_same(obj, new_obj)
    end

    it "allows overrding the data of the given PDF object" do
      obj = @doc.wrap({a: :b}, oid: 10, gen: 20, stream: 'hallo')
      new_obj = @doc.wrap(obj, oid: 15, gen: 25, stream: 'not')
      assert_equal('not', new_obj.raw_stream)
      assert_equal(15, new_obj.oid)
      assert_equal(25, new_obj.gen)
    end

    it "sets the given oid/gen values on the returned object" do
      obj = @doc.wrap(5, oid: 10, gen: 20)
      assert_equal(10, obj.oid)
      assert_equal(20, obj.gen)
    end

    it "uses the type/subtype information in the hash that should be wrapped" do
      assert_kind_of(@myclass2, @doc.wrap({Type: :MyClass, Subtype: :TheSecond}))
    end

    it "respects the given type/subtype arguments" do
      assert_kind_of(@myclass, @doc.wrap(5, type: :MyClass))
      assert_kind_of(@myclass2, @doc.wrap(5, type: :MyClass, subtype: :TheSecond))
    end
  end

  describe "unwrap" do
    it "returns a simple native ruby type" do
      assert_equal(5, @doc.unwrap(5))
    end

    it "recursively unwraps arrays" do
      assert_equal([5, 10, [200]],
                   @io_doc.unwrap([5, HexaPDF::PDF::Reference.new(1, 0), [HexaPDF::PDF::Reference.new(2, 0)]]))
    end

    it "recursively unwraps hashes" do
      assert_equal({a: 5, b: 10, c: [200]},
                   @io_doc.unwrap({a: 5, b: HexaPDF::PDF::Reference.new(1, 0),
                                    c: [HexaPDF::PDF::Reference.new(2, 0)]}))
    end

    it "recursively unwraps PDF objects" do
      assert_equal({a: 10}, @io_doc.unwrap(@io_doc.wrap({a: HexaPDF::PDF::Reference.new(1, 0)})))
    end

    it "fails to unwrap recursive structures" do
      obj1 = @doc.add({})
      obj2 = @doc.add({})
      obj1.value[2] = obj2
      obj2.value[1] = obj1
      assert_raises(HexaPDF::Error) do
        @doc.unwrap(@doc.wrap({a: obj1}))
      end
    end
  end

  describe "each" do
    it "iterates over the current objects" do
      assert_equal([nil, 10, 200], @io_doc.each(current: true).sort.map(&:value))
    end

    it "iterates over all objects" do
      assert_equal([nil, 10, 200, 20], @io_doc.each(current: false).sort.map(&:value))
    end
  end

end