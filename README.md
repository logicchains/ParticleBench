ParticleBench
=============

OpenGL particle animation benchmark of various languages

Compile instructions: 

clang C.c -std=c99 -O3 -lGL -lGLU -lglfw3 -lX11 -lXxf86vm -lXrandr -lpthread -lXi -lm (gcc 4.72 doesn't work for me, llvm 3.2 does) 

go build Go.go
