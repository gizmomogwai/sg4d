import std;
int main(string[] args) {
    writeln(args[1]
        .split("\n")
        .map!(line => line.split("="))
        .filter!(keyValue => keyValue[1] == "true")
        .map!(keyValue => keyValue[0])
        .array
        );
return 0;
}
