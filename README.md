ParticleBench
=============

OpenGL particle animation benchmark of various languages

Compile instructions: 

clang C.c -std=c99 -O3 -lGL -lGLU -lglfw3 -lX11 -lXxf86vm -lXrandr -lpthread -lXi -lm -lGLEW (gcc 4.72 doesn't work for me, llvm 3.2 does) 

go build Go.go

dmd D.d -L-lDerelictGLFW3 -L-lDerelictUtil -L-ldl -L-lDerelictGL3 -O -release -inline

rustc R.rs --opt-level=3

racket Rkt.rkt

javac -classpath "jar/gluegen-rt.jar:jar/jogl-all.jar" ./Java.java 

java -classpath "jar/gluegen-rt.jar:jar/jogl-all.jar:." -Djava.library.path=lib Java

mcs CS.cs -r:OpenTK.dll -unsafe

mono CS.exe

python Py.py

In SBCL repl: (load "Lisp.lisp") then (pb:run). It requires Quicklisp.
