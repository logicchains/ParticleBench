ParticleBench
=============

OpenGL particle animation benchmark of various languages

Compile instructions: 

clang C.c -std=c99 -O3 -lGL -lGLU -lglfw3 -lX11 -lXxf86vm -lXrandr -lpthread -lXi -lm -lGLEW (gcc 4.72 doesn't work for me, llvm 3.2 does) 

g++ CPP.cpp -std=c++11 -O3 -lGL -lGLU -lglfw3 -lX11 -lXxf86vm -lXrandr -lpthread -lXi -lm -lGLEW (works with 4.7.3-1ubuntu1)

go build Go.go

dmd D.d -L-lDerelictGLFW3 -L-lDerelictUtil -L-ldl -L-lDerelictGL3 -O -release -inline

rustc R.rs --opt-level=3

racket Rkt.rkt

javac -classpath "lwjgl-2.9.0/jar/jinput.jar:lwjgl-2.9.0/jar/lwjgl.jar:lwjgl-2.9.0/jar/lwjgl_util.jar" ./ParticleBench.java

java -classpath "lwjgl-2.9.0/jar/jinput.jar:lwjgl-2.9.0/jar/lwjgl.jar:lwjgl-2.9.0/jar/lwjgl_util.jar:." -Djava.library.path=lwjgl-2.9.0/native/linux ParticleBench

mcs CS.cs -r:OpenTK.dll -unsafe

mono CS.exe

python Py.py

sbcl --load Lisp.lisp --eval "(pb:run)"

lein run (Clojure, requires leningen)
