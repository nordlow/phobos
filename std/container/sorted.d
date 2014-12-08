module std.container.sorted;

import std.range;
import std.traits;

public import std.container.util;

// Sorted adapter 
/**
Implements a automatically sorted 
container on top of a given random-access range type (usually $(D
T[])) or a random-access container type (usually $(D Array!T)). The
documentation of $(D Sorted) will refer to the underlying range or
container as the $(I store) of the heap.

If $(D Store) is a range, the $(D Sorted) cannot grow beyond the
size of that range. If $(D Store) is a container that supports $(D
insertBack), the $(D Sorted) may grow by adding elements to the
container.
     */
struct Sorted(Store, alias less = "a < b")
{
    private: 
    // Comparison predicate
	alias comp = binaryFun!(less);
	static if(isRandomAccessRange!(Store))
	{
		alias _Range = SortedRange!(Store, comp);
		alias StoreRange = Range;
		enum storeIsContainer = false;
	}
 	else static if(isRandomAccessRange!(typeof(Store.init[])))
	{
		alias _Range = SortedRange!(Store.Range, comp);
		alias StoreRange = Store.Range;
		enum storeIsContainer = true;
	}
	else
		static assert(false, "Store must be a random access range or a container providing one");

	alias Element = ElementType!_Range;	

	// disable assignment via Range
	static struct Range
	{
		@property 
		_Range payload;
		alias payload this;
		
		@property 
		auto ref const(Element) front() { return payload.front; }
		@property
		auto ref const(Element) back() { return payload.front; }
		@disable void opIndexAssign();
		@disable void opIndexOpAssign();
	}

	public:

    import std.functional : binaryFun;
    import std.exception : enforce;
    import std.range: SortedRange;
    import std.algorithm : move, min;
    import std.typecons : RefCounted, RefCountedAutoInitialize;

// Really weird @@BUG@@: if you comment out the "private:" label below,
// std.algorithm can't unittest anymore
//private:

    // The payload includes the support store and the effective length
    private static struct Data
    {
        Store _store;
        size_t _length;
    }
    private RefCounted!(Data, RefCountedAutoInitialize.no) _payload;
    // Convenience accessors
    private @property ref Store _store()
    {
        assert(_payload.refCountedStore.isInitialized);
        return _payload._store;
    }
    private @property ref size_t _length()
    {
        assert(_payload.refCountedStore.isInitialized);
        return _payload._length;
    }


    // Asserts that the store is sorted 
    private void assertValid()
    {
        debug
        {
			assert(std.algorithm.isSorted!(comp)(_store()));
        }
    }

public:

    /**
       Sorts store.  If $(D initialSize) is
       specified, only the first $(D initialSize) elements in $(D s)
       are transformed into a heap, after which the heap can grow up
       to $(D r.length) (if $(D Store) is a range) or indefinitely (if
       $(D Store) is a container with $(D insertBack)). Performs
       $(BIGOH min(r.length, initialSize)) evaluations of $(D less).
     */
    this(Store s, size_t initialSize = size_t.max)
    {
        acquire(s, initialSize);
    }

/**
Takes ownership of a store. After this, manipulating $(D s) may make
brake Sorted
     */
    void acquire(Store s, size_t initialSize = size_t.max)
    {
        _payload.refCountedStore.ensureInitialized();
        _store = move(s);
        _length = min(_store.length, initialSize);
        if (_length < 2) return;

		std.algorithm.sort!(comp)(_store[0 .. _length]);		
        assertValid();
    }



/**
Takes ownership of a store assuming it already was sorted
	*/
    void assume(Store s, size_t initialSize = size_t.max)
    {
        _payload.refCountedStore.ensureInitialized();
        _store = s;
        _length = min(_store.length, initialSize);
        assertValid();
    }

/**
Release the store. Returns the portion of the store from $(D 0) up to
$(D length). The return value is sorted.
     */
    auto release()
    {
        if (!_payload.refCountedStore.isInitialized)
        {
            return typeof(_store[0 .. _length]).init;
        }
        assertValid();
        auto result = _store[0 .. _length];
        _payload = _payload.init;
        return result;
    }

/**
Returns $(D true) if the store is _empty, $(D false) otherwise.
     */
    @property bool empty()
    {
        return !length;
    }

/**
Returns a wrapped duplicate of the store. The underlying store must also
support a $(D dup) method.
     */
    @property Sorted dup()
    {
        Sorted result;
        if (!_payload.refCountedStore.isInitialized) return result;
        result.assume(_store.dup(), length);
        return result;
    }

/**
Returns the _length of the store.
     */
    @property size_t length()
    {
        return _payload.refCountedStore.isInitialized ? _length : 0;
    }

/**
Returns the _capacity of the store, which is the length of the
underlying store (if the store is a range) or the _capacity of the
underlying store (if the store is a container).
     */
    @property size_t capacity()
    {
        if (!_payload.refCountedStore.isInitialized) return 0;
        static if (is(typeof(_store.capacity) : size_t))
        {
            return _store.capacity;
        }
        else
        {
            return _store.length;
        }
    }

/**
Returns a copy of the _front of the heap, which is the smallest element
according to $(D less).
     */
    @property ElementType!Store front()
    {
        enforce(!empty, "Cannot call front on an empty range.");
        return _store.front;
    }

/**
Returns a copy of the _back of the heap, which is the biggest element
according to $(D less).
     */
    @property ElementType!Store back()
    {
        enforce(!empty, "Cannot call back on an empty range.");
        return _store[_length - 1];
    }

/**
Clears the heap by detaching it from the underlying store.
     */
    void clear()
    {
        _payload = _payload.init;
    }


	size_t _insert(Value)(Value value)
	{
        _payload.refCountedStore.ensureInitialized();
        static if (is(typeof(_store.insertBack(value))))
        {
            if (length == _store.length)
            {
                // reallocate
                _store.insertBack(value);
            }
            else
            {
                // no reallocation
                _store[_length] = value;
            }
        }
        else
        {
            // can't grow
            enforce(length < _store.length,
                    "Cannot grow Sorted created over a range");
            _store[_length] = value;
        }
        ++_length;
	
		return 1;
	}

/**
Inserts $(D value) into the store. If the underlying store is a range
and $(D length == capacity), throws an exception.
     */
    // Insert one item
    size_t insertBack(Value)(Value value)
        if (isImplicitlyConvertible!(Value, ElementType!Store))
    {
		_insert(value);
		std.algorithm.completeSort!(comp)(assumeSorted!comp(_store[0 .. _length-1]), _store[_length-1 .. _length]);	
        debug(Sorted) assertValid();
        return 1;
    }
/** 
	Inserts all elements of range $(D stuff) into store. If the underlying
	store is a range and has not enough space left, throws an exception.
	*/
    size_t insertBack(Range)(Range stuff)
        if (isInputRange!Range 
		   && isImplicitlyConvertible!(ElementType!Range, ElementType!Store))
	{
        _payload.refCountedStore.ensureInitialized();

		static if(!storeIsContainer && hasLength!Range)
		{
			enforce(stuff.length > capacity - _length, 
				"Cannot grow underlying range");
		}

		// reserve space if underlying container supports it
		static if(__traits(compiles, _store.reserve(stuff.length)))
			_store.reserve(stuff.length);

		// insert all at once, if possible
		static if(__traits(compiles, _store.insertBack(stuff)))
		{
			size_t count = _store.insertBack(stuff);
			_length += count;
		}
		else
		{
			size_t count;
			foreach(s; stuff) 
			{ 
				_insert(s);
				count += 1;
			}
		}

		assert(count <= _length);
		std.algorithm.completeSort!(comp)(assumeSorted!comp(_store[0 .. _length-count]), _store[_length-count .. _length]);	
        debug(Sorted) assertValid();
        return 1;
	}

	/// ditto	
	alias insert = insertBack;


/**
	  Removes the given range from the store. Note that
	  this method requires r to be optained from this store
	  and the store to be a container.
	 */
	void remove(Range r)
	{
		import std.algorithm : swapRanges;
		size_t count = r.length;
		// if the underlying store supports it natively
		static if(__traits(compiles, _store.remove(r)))
			_store.remove(r);
		else
			// move elements to the end and reduce length of array
			swapRanges(r.payload, retro(this[].payload));

		_length -= count;
	
		assertValid();	
	}

/+
/**
	  Removes the given range from the store. Note that
	  this method requires r to be optained from this store
	  and the store to be a container.
	 */

	void remove(Take!Range r)
	{
		import std.algorithm : swapRanges;
		size_t count = r.length;
		// if the underlying store supports it natively
		static if(__traits(compiles, _store.remove(r)))
			_store.remove(r);
		else
			// move elements to the end and reduce length of array
			swapRanges(r.payload, retro(this[].payload));

		_length -= count;
	
		assertValid();	
	}
+/
/**
Removes the largest element 
     */
    void removeBack()
    {
        enforce(!empty, "Cannot call removeFront on an empty range.");
        --_length;
    }

    /// ditto
    alias popBack = removeBack;


/**
Removes the largest element from the heap and returns a copy of
it. The element still resides in the heap's store. For performance
reasons you may want to use $(D removeFront) with heaps of objects
that are expensive to copy.
     */
    ElementType!Store removeAny()
    {
        removeBack();
        return _store[_length];
    }

/** 
Return SortedRange for _store
	*/
	Range opIndex()
	{
		import std.range : assumeSorted;
		return Range(_store[0 .. _length].assumeSorted!comp);
	}

/**
	Return SortedRange for _store
	*/
	Range opIndex(size_t start, size_t stop)
	{
		return Range(_store[0 .. _length].assumeSorted!comp);
	}

/**
	Return element at index $(D idx)
	*/
	auto ref const(Element) opIndex(size_t idx)
	{
		return _store[idx];
	}

	size_t opSlice() { return _length; }



/**
Container primitives
	*/
	Range lowerBound(Value)(Value val)
	{
		return Range(this[].lowerBound(val));
	}	

/// ditto
	Range upperBound(Value)(Value val)
	{
		return Range(this[].upperBound(val));
	}	

/// ditto
	Range equalRange(Value)(Value val)
	{
		return Range(this[].equalRange(val));
	}	
}

/**
Convenience function that returns a $(D BinaryHeap!Store) object
initialized with $(D s) and $(D initialSize).
 */
Sorted!(Store, less) sorted(alias less = "a < b", Store)(Store s,
        size_t initialSize = size_t.max)
{
    return Sorted!(Store, less)(s, initialSize);
}

/// Example sorting an array by wrapping it in Sorted
unittest
{
    import std.algorithm : equal, isSorted;
    int[] a = [ 4, 1, 3, 2, 16, 9, 10, 14, 8, 7 ];
    auto s = sorted(a);
    // largest element
    assert(s.back == 16);
	// smallest element
	assert(s.front == 1);
	
    // aassert that s is sorted 
	assert(isSorted(s.release()));	
}

/// Call opIndex on $(D Sorted) to optain a $(D SortedRange). 
unittest
{
	import std.container : Array;
    enum int[] data = [ 4, 1, 3, 2, 16, 9, 10, 14, 8, 7 ];
	foreach(T; TypeTuple!(int[], Array!int))
	{
    	import std.algorithm : equal;
    	import std.range : take;
    	T store = [4, 1, 3, 2, 16, 9, 10, 14, 8, 7];
		auto sortedArray = sorted!("a > b")(store);
    	auto sr = sortedArray[];
    	auto top5 = sr.take(5);
    	assert(top5.equal([16, 14, 10, 9, 8]));
		
		assert(equal(sr.lowerBound(7), [16, 14, 10, 9, 8]));
		assert(equal(sr.upperBound(7), [4, 3, 2, 1]));
		assert(equal(sr.equalRange(7), [7]));

		// lowerBound, upperBound and equalRange are 
		// container primitives and should work on Sorted directly
		assert(equal(sortedArray.lowerBound(7), [16, 14, 10, 9, 8]));
		assert(equal(sortedArray.upperBound(7), [4, 3, 2, 1]));
		assert(equal(sortedArray.equalRange(7), [7]));
	}	
	
}

unittest
{
	import std.container : Array;
    enum int[] data = [ 4, 1, 3, 2, 16, 9, 10, 14, 8, 7 ];
	foreach(T; TypeTuple!(int[], Array!int))
    {
        T a = data;
        auto h = sorted!("a > b")(a);
        assert(h.front == 16);
        assert(equal(a[], [ 16, 14, 10, 9, 8, 7, 4, 3, 2, 1 ]));
        auto witness = [ 16, 14, 10, 9, 8, 7, 4, 3, 2, 1 ];
        for (; !h.empty; h.removeBack(), witness.popBack())
        {
            assert(!witness.empty);
            assert(witness.back == h.back);
        }
        assert(witness.empty);
    }
}

// remove elements via range
unittest
{
	{
		import std.container : Array;
    	enum int[] a = [ 4, 1, 3, 2, 16, 9, 10, 14, 8, 7 ];
		foreach(T; TypeTuple!(int[], Array!int))
		{
			T store = a;
    		auto s = sorted!("a < b")(store);
    		assert(s.back == 16);

			auto removeThese = s[].drop(s.length - 4);
			s.remove(removeThese);

			assert(s.back == 8);
		}
	}
}

unittest
{
	int[] a = [1, 2, 3, 4];
	auto sa = sorted(a);
	auto s = sa[];
	static assert(!is(typeof(s.front() = 12)));
	static assert(!is(typeof(s.back() = 12)));
	static assert(!is(typeof(s[1] = 12)));
}

// test insertion
unittest 
{
	import std.array, std.random, std.container;
	{
		int[] inputs = iota(20).map!(x => uniform(0, 1000)).array;
		auto sa = Sorted!(Array!int)();
		foreach(i; inputs)
			sa.insertBack(i);

		foreach(idx; 1 .. sa.length())
			assert(sa[idx-1] <= sa[idx]);

		assert(sa.length == 20);
	}
	{
		auto inputs = iota(20).map!(x => uniform(0, 1000));
		auto sa = Sorted!(Array!int)();
		sa.insertBack(inputs);

		foreach(idx; 1 .. sa.length())
			assert(sa[idx-1] <= sa[idx]);
		
		assert(sa.length == 20);
	}
}
