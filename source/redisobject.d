module redisobject;

import std.traits;
import std.container;
import std.functional;
import std.stdio;
import std.conv;
import std.range;
import std.string;

template InnerType(T) {
	alias InnerType = T;
}

template InnerType(T : T[]) {
	alias InnerType = T;
}

//Checks if the wrapped version of the original type 'Original' exists and returns the generated
//structure if not.
template CheckForBuiltType(alias Original) {
	static if (!is(typeof(mixin("Redis" ~ Original.stringof)))) {		
		enum CheckForBuiltType = MapToRedis!Original;
	} else {
		enum CheckForBuiltType = "";
	}
}

class RedisList(Original) {
	//check if the Wrapped class for the Original type does exists
	mixin(CheckForBuiltType!Original);
	mixin("alias T = Redis" ~ Original.stringof ~ ";");

	const string key = "#%s:lst".format(Original.stringof);

	static T make() {
		T lst;
		lst.key = key + to!string(1);

		return lst;
	}

	void setParentKey(string parentKey) {
		key = parentKey ~ T.stringof ~ "s";
	}

	T opIndex(size_t index) {
		return T.fetch(key ~ to!string(index));
	}
	
	T[] opSlice(size_t start, size_t end)
	in {
		assert (start < end);
	}
	body {
		T[] results = new T[end - start];

		foreach (i; start..end) {
			results[i - start] = T.fetch(key ~ to!string(i));
		}
		
		return results;
	}
}

struct RedisValue(T) {
	T value;
	alias value this;
}

private void setChildKeys(Decorated)(Decorated d) {
	foreach(member; __traits(derivedMembers, Decorated)) {
		alias MemberType = typeof(__traits(getMember, d, member));
		static if (hasMember!(MemberType, "setParentKey")) {
			__traits(getMember, d, member).setParentKey(d.key);
		}
	}
}

template RedisObject(Decorated, Original) {        
    const static string identifier = Original.stringof;
	string key;

    void save() {
        foreach(member; __traits(derivedMembers, Decorated)) {
			alias MemberType = typeof(__traits(getMember, Decorated, member));
			static if (hasMember!(MemberType, "save")) {
				__traits(getMember, this, member).save();
			}
        }
    }

	public static Decorated make() {
		auto d = new Decorated();
		d.key = "#%s:%d".format(identifier, to!string(1));

		foreach(member; __traits(derivedMembers, Decorated)) {
			alias MemberType = typeof(__traits(getMember, Decorated, member));
			static if (hasMember!(MemberType, "make")) {
				__traits(getMember, d, member) = MemberType.make();
			}
		}

		setChildKeys(d);

		d.save();

		return d;
	}

    public static Decorated fetch(string key) {
		Decorated d = new Decorated();
		d.key = key;

		setChildKeys(d);

		return d;
    }

	private this() {
	}
}

string MapToRedis(T)() {
	string injectedTypes;

	foreach(member; __traits(derivedMembers, T)) {
		alias MemberType = typeof(__traits(getMember, T, member));
		static if (isBasicType!MemberType) {
			injectedTypes ~= q{
				RedisValue!%s %s;
			}.format(MemberType.stringof, member);
		} else if (isArray!MemberType) {
			injectedTypes ~= q{
			    RedisList!%s %s;
			}.format(InnerType!MemberType.stringof, member);
		} else if (isAssociativeArray!MemberType) {

		} else if (is(MemberType == class)) {
			injectedTypes ~= q{
				Redis%s %s;
			}.format(MemberType.stringof, member);
		}
	}
	
	return q{
		class Redis%s {
			mixin RedisObject!(Redis%s, %s);
			%s
		}
	}.format(T.stringof, T.stringof, T.stringof, injectedTypes);
}


version(unittest) {
	class A {
		long value1;
		B b;
	}

	class B {
		A[] a1;
		A[] a2;
	}
	
	mixin (MapToRedis!B);
	mixin (MapToRedis!A);
}

unittest {
	static assert (is(typeof(RedisB.a1) == RedisList!A));
	static assert (is(typeof(RedisB.a2) == RedisList!A));
	static assert (is(typeof(RedisB.a1) == typeof(RedisB.a2)));
	static assert (is(typeof(RedisA.b)));
	static assert (is(typeof(RedisA.b) == RedisB));
}

unittest {
	RedisA a = RedisA.make();

	assert(a.key == "#A:1", "The generated key should be #A:1, it is " ~ a.key);
	assert(a.b.key == "#B:1", "The generated key should be #B:1, it is " ~ a.b.key);
}

unittest {
	RedisB b = RedisB.make();

	assert(b.a1.key == "#B:1:a1#A:lst:1", "The generated key should be #B:1:a1#A:lst:1, it is " ~ b.a1.key);
	//RedisList!A a;
	//a.key == "#RedisA:lst:1";
}