import core.thread;
import sg.window;
import sg;
import std;

import autoptr.common;
import autoptr.intrusive_ptr;

auto triangle(float rotationSpeed)
{
    Texture[] textures;
    auto rotation = TransformationGroup.make("rotation", mat4.identity);
    auto appearance = Appearance.make("position_color_texture", textures);
    auto shape = ShapeGroup.make("triangle", new Triangle("tri"), appearance);
    rotation.get.addChild(shape);
    float rot = 0.5;
    rotation.get.addChild(IntrusivePtr!Behavior.make("rotY-%s".format(rotationSpeed), {
            //auto xScale = (sin(rot)+1)*0.5+0.2;
            //auto yScale = (sin(rot)+1)*0.5+0.2;
            rotation.get.setTransformation(mat4.rotation(rot, vec3(1, 1, 1))); //.scale(xScale, yScale, 1));
            rot = cast(float)(rot + rotationSpeed);
        }));
    return rotation;
}

auto cube(string name, Texture texture, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = TransformationGroup.make("translation-" ~ name, mat4.translation(x, y, z));
    auto rotation = TransformationGroup.make("rotation-" ~ name, mat4.identity());
    Texture[] textures = [texture];
    // dfmt off
    auto shape =
        ShapeGroup.make("cube-" ~ name,
                  indexed ?
                      new IndexedInterleavedCube("cube(size=1)", 100)
                      : new TriangleArrayCube("cube", 100),
                        Appearance.make("position_color_texture", textures)
        );
    // dfmt on
    rotation.get.addChild(shape);
    float rot = 0.5;
    // dfmt off
    rotation.get.addChild(
        IntrusivePtr!Behavior.make("rotY-" ~ name,
            {
                auto xScale = (sin(rot)+1)*0.5+0.2;
                auto yScale = (sin(rot)+1)*0.5+0.2;
                rotation.get.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)).scale(xScale, yScale, 1));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.get.addChild(rotation);
    return translation;
}

Projection getProjection(string[] args)
{
    if (args.length > 1)
    {
        switch (args[1])
        {
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

void main(string[] args)
{
    auto scene = Scene.make("scene");
    auto projection = getProjection(args);
    auto observer = Observer.make("observer", projection);
    scene.get.addChild(observer);
    scope window = new Window(scene, 800, 600, (Window w, int key, int, int action, int) {
        auto o = observer.get;
        auto oldPosition = o.getPosition;
        if (key == 'W')
        {
            o.setPosition(vec3(oldPosition.xy, o.getPosition.z - 1));
        }
        if (key == 'S')
        {
            o.setPosition(vec3(oldPosition.xy, o.getPosition.z + 1));
        }
        if (key == 'A')
        {
            o.setPosition(vec3(oldPosition.x - 1, oldPosition.yz));
        }
        if (key == 'D')
        {
            o.setPosition(vec3(oldPosition.x + 1, oldPosition.yz));
        }
    });

    if (cast(ParallelProjection) projection)
    {
        observer.get.setPosition(vec3(-window.getWidth() / 2, -window.getHeight() / 2, 300));
        auto image1 = read_image("image1.jpg");
        observer.get.addChild(cube("cube", Texture.make(image1), 0, 0, 0, 0.001, true));
        observer.get.addChild(cube("cube", Texture.make(image1), -200, 0, 0, 0.0005, false));
    }
    else if (cast(CameraProjection) projection)
    {
        observer.get.setPosition(vec3(0, 0, 300));
        auto image1 = read_image("image1.jpg");
        observer.get.addChild(cube("cube", Texture.make(image1), 0, 0, 0, 0.001, true));
        observer.get.addChild(cube("cube", Texture.make(image1), -200, 0, 0, 0.0005, false));
    }
    else if (cast(IdentityProjection) projection)
    {
        observer.get.addChild(triangle(0.001));
    }

    scene.get.accept(new PrintVisitor);

    scope renderVisitor = new RenderVisitor(window);
    auto visitors = [renderVisitor, new BehaviorVisitor(),];
    while (!glfwWindowShouldClose(window.window))
    {
        foreach (visitor; visitors)
        {
            scene.get.accept(visitor);
        }

        glfwSwapBuffers(window.window);

        // poll glfw and scene graph "events"
        glfwPollEvents();
        receiveTimeout(msecs(-1), (shared void delegate() codeForOglThread) {
            codeForOglThread();
        });
    }
}
