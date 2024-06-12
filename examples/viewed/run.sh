#!/bin/sh
env DYLD_LIBRARY_PATH=/opt/homebrew/Cellar/glfw/3.4/lib dub run --config=opengl33 --build=release -- --directory=~/Pictures/CopyOfImageLib/2008/01/ --deepface=true
