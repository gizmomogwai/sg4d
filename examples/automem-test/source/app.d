import automem;
import sg;
import std;
void main(string[] args) {
    auto a = Appearance.init;
    writeln(a);
    class _My {
        int i;
        this(int i) {
            this.i = i;
        }

        ~this() {
            writeln("~My", i);
        }
    }
    alias My = RefCounted!_My;

    auto m = My(1);
    {

        Vector!My v1 = vector(m, My(3), My(4));
        writeln(0);
        v1.free;
        writeln(0.1);
        Vector!My v2 = vector(m, My(5));
        writeln(v1);
        writeln(v2);
        v1[0] = My(6);
        /*
          auto  v = RefCounted!(Vector!(RefCounted!My))(new My(1), new My(2), new My(3));
          {
          auto v2 = v;
          v[0] = new My(4);
          }
          v = vector(new My(5));
        */
        writeln(1);
    }
    writeln(2);
}
