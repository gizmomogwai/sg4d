import std.stdio;
import core.thread;
import std.conv;
import std.string;
import std.concurrency;
import argparse;

static struct Args
{
    enum Projection
    {
        parallel,
        camera
    }

    @(NamedArgument().Required())
    Projection projection;
}

import sg;
import window;

auto cube(string textureFile, float x, float y, float z, float rotationSpeed, bool indexed)
{
    auto translation = new TransformationNode("translation-" ~ textureFile,
            mat4.translation(x, y, z));
    auto rotation = new TransformationNode("rotation-" ~ textureFile, mat4.identity());
    IFImage image = read_image(textureFile, 3);
    if (image.e)
    {
        throw new Exception("%s".format(IF_ERROR[image.e]));
    }
    // dfmt off
    auto shape =
        new Shape("cube-" ~ textureFile,
                  indexed ?
                      new IndexedInterleavedCube("cube(size=1)", 1)
                      : new TriangleArrayCube("cube", 1),
                  new Appearance([new Texture(image)])
        );
    // dfmt on
    rotation.addChild(shape);
    float rot = 0;
    // dfmt off
    rotation.addChild(
        new Behavior("rotY-" ~ textureFile,
            {
                rotation.setTransformation(mat4.rotation(rot, vec3(1, 1, 1)));
                rot = cast(float)(rot + rotationSpeed);
            }
        )
    );
    // dfmt on
    translation.addChild(rotation);
    return translation;
}

auto cubeSlow(string textureFile, float x, float y, float z, float rotationSpeed, bool indexed)
{
    Thread.sleep(dur!"seconds"(5));
    return cube(textureFile, x, y, z, rotationSpeed, indexed);
}

Projection toProjection(Args.Projection projection)
{
    switch (projection)
    {
    case Args.Projection.parallel:
        return new ParallelProjection(1, 1000);
    case Args.Projection.camera:
        return new CameraProjection(1, 1000);
    default:
        throw new Exception("Unknown projection: %s".format(projection));
    }
}

mixin Main.parseCLIArgs!(Args, (Args args) {
    auto scene = new Scene("scene");
    auto projection = args.projection.toProjection;
    auto observer = new Observer("observer", projection);
    scene.addChild(observer);
    observer.addChild(cube("image1.jpg", 0, 0, 0, 0.01, false));
    observer.addChild(cube("image2.jpg", 3, 0, 0, 0.02, true));
    auto mainTid = thisTid;
    auto window = new Window(scene, 800, 600, (int key, int, int action, int) {
        if (key == 'A')
        {
            observer.strafeLeft();
            return;
        }
        if (key == 'D')
        {
            observer.strafeRight();
            return;
        }
        if (key == 'W')
        {
            observer.forward();
            return;
        }
        if (key == 'S')
        {
            observer.backward();
            return;
        }
        if (key == 'P')
        {
            scene.accept(new PrintVisitor());
            return;
        }
        if ((key == '1') && (action == GLFW_RELEASE))
        {
            new Thread({
                try
                {
                    import std.random;

                    auto cube = cubeSlow("image1.jpg", uniform(0, 10), 0, 0, 0.05, false);
                    mainTid.send(cast(shared) { observer.addChild(cube); });
                }
                catch (Exception e)
                {
                    writeln(e);
                }
            }).start();
        }
    });

    PrintVisitor v = new PrintVisitor();
    scene.accept(v);

    Visitor[] visitors = [new OGLRenderVisitor(window), new BehaviorVisitor()];

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

});
