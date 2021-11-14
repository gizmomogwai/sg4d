import core.thread;
import sg.window;
import sg;
import std;

auto triangle(float rotationSpeed) {
    Textures textures;
    auto rotation = new TransformationNode("rotation", mat4.identity);
    auto shape = new Shape("triangle", new Triangle("tri"), new Appearance(textures));
    rotation.addChild(shape);
    float rot = 0.5;
    rotation.addChild(
        new Behavior("rotY-" ~ name,
                     {
                         //auto xScale = (sin(rot)+1)*0.5+0.2;
                         //auto yScale = (sin(rot)+1)*0.5+0.2;
                         rotation.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)));//.scale(xScale, yScale, 1));
                         rot = cast(float)(rot + rotationSpeed);
                     }
        )
    );
    return rotation;
}

auto cube(string name, Texture texture, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = new TransformationNode("translation-" ~ name, mat4.translation(x, y, z));
    auto rotation = new TransformationNode("rotation-" ~ name, mat4.identity());
    // dfmt off
    auto shape =
        new Shape("cube-" ~ name,
                  indexed ?
                      new IndexedInterleavedCube("cube(size=1)", 100)
                      : new TriangleArrayCube("cube", 100),
                  new Appearance(Textures(texture))
        );
    // dfmt on
    rotation.addChild(shape);
    float rot = 0.5;
    // dfmt off
    rotation.addChild(
        new Behavior("rotY-" ~ name,
            {
                auto xScale = (sin(rot)+1)*0.5+0.2;
                auto yScale = (sin(rot)+1)*0.5+0.2;
                rotation.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)).scale(xScale, yScale, 1));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.addChild(rotation);
    return translation;
}

Projection getProjection(string[] args) {
    if (args.length > 1) {
        switch (args[1]) {
        case "parallel":
            return new ParallelProjection(1, 1000, 1);
        case "camera":
            return new CameraProjection(1, 1000);
        case "id":
        default:
            return new IdentityProjection();
        }
    }
    return new IdentityProjection();
}
void main(string[] args) {
    auto scene = new Scene("scene");
    auto projection = getProjection(args);
    auto observer = new Observer("observer", projection);
    scene.addChild(observer);
    auto window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
            auto oldPosition = observer.getPosition;
            if (key == 'W') {
                observer.setPosition(vec3(oldPosition.xy, observer.getPosition.z-1));
            }
            if (key == 'S') {
                observer.setPosition(vec3(oldPosition.xy, observer.getPosition.z+1));
            }
            if (key == 'A') {
                observer.setPosition(vec3(oldPosition.x - 1, oldPosition.yz));
            }
            if (key == 'D') {
                observer.setPosition(vec3(oldPosition.x + 1, oldPosition.yz));
            }
            writeln(observer.getPosition);
        });

    if (cast(ParallelProjection)projection) {
        observer.setPosition(vec3(-window.getWidth()/2, -window.getHeight()/2, 300));
        auto image1 = read_image("image1.jpg");
        observer.addChild(cube("cube", Texture(image1), 0, 0, 0, 0.001, false));
        observer.addChild(cube("cube", Texture(image1), -200, 0, 0, 0.0005, false));
    } else if (cast(CameraProjection)projection) {
        observer.setPosition(vec3(0, 0, 300));
        auto image1 = read_image("image1.jpg");
        observer.addChild(cube("cube", Texture(image1), 0, 0, 0, 0.001, false));
        observer.addChild(cube("cube", Texture(image1), -200, 0, 0, 0.0005, false));
    } else if (cast(IdentityProjection)projection) {
        observer.addChild(triangle(0.001));
    }

    auto visitors = [new TheRenderVisitor(window), new BehaviorVisitor(),];
    while (!glfwWindowShouldClose(window.window))
    {
        foreach (visitor; visitors)
        {
            scene.accept(visitor);
        }

        glfwSwapBuffers(window.window);

        // poll glfw and scene graph "events"
        glfwPollEvents();
        receiveTimeout(msecs(-1), (shared void delegate() codeForOglThread) {
            codeForOglThread();
        });
    }
}
