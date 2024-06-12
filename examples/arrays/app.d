#!/usr/bin/env dub
/+
 dub.sdl:
 name "hello"
 dependency "autoptr" version=">=0.6.0-rc4 <0.7.0-0"
 dependency "emsi_containers" version="~>0.9.0"
 +/
import autoptr.common;
import autoptr.intrusive_ptr;
import containers.dynamicarray;
import core.stdc.stdio;
import std.stdio;

class AData
{
    SharedControlType referenceCounter;
    int i;
    this(int i)
    {
        this.i = i;
    }

    ~this() @nogc
    {
        printf("AData %d\n", i);
    }
}

alias A = IntrusivePtr!AData;

class CData : AData
{
    this(int i)
    {
        super(i);
    }

    ~this() @nogc
    {
        printf("CData %d\n", i);
    }
}

alias C = IntrusivePtr!CData;

class BData
{
    SharedControlType referenceCounter;
    DynamicArray!A arr;
    int i;
    this(int i)
    {
        this.i = i;
    }

    void add(T)(T a)
    {
        A h = a;
        arr.insertBack(h);
    }

    ~this() @nogc
    {
        printf("BData %d\n", i);
    }
}

alias B = IntrusivePtr!BData;

void main(string[] args)
{
    {
        auto b = B.make(1);
        {
            auto a1 = A.make(2);
            writeln("adding a1");
            b.get.add(a1);
            auto a2 = A.make(3);
            writeln("adding a2");
            b.get.add(a2);
            auto c1 = C.make(4);
            writeln("adding c1");
            b.get.add(c1);
        }
        for (int i = 0; i < b.get.arr.length; ++i)
        {
            writeln("b.get.arr[", i, "].useCount: ", b.get.arr[i].useCount);
        }
        import core.memory;

        writeln("before collect");
        GC.collect();
        writeln("after collect");
        for (int i = 0; i < b.get.arr.length; ++i)
        {
            writeln("b.get.arr[", i, "].useCount: ", b.get.arr[i].useCount);
        }
    }
}
