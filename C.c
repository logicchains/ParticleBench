#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

#include <GL/glew.h>
#include <GLFW/glfw3.h>

#define TITLE "ParticleBench"
#define WIDTH 800
#define HEIGHT 600

#define MIN_X -80
#define MAX_X 80
#define MIN_Y -90
#define MAX_Y 50
#define MIN_DEPTH 50
#define MAX_DEPTH 250

#define START_RANGE 15
#define START_X (MIN_X + (MIN_X+MAX_X)/2)
#define START_Y MAX_Y
#define START_DEPTH (MIN_DEPTH + (MIN_DEPTH+MAX_DEPTH)/2)

#define POINTS_PER_SEC 2000
#define MAX_INIT_VEL 7
#define MAX_LIFE 5000
#define MAX_SCALE 4

#define WIND_CHANGE 2000
#define MAX_WIND 3
#define SPAWN_INTERVAL 0.01 
#define RUNNING_TIME ((MAX_LIFE / 1000) * 5)
#define MAX_PTS (RUNNING_TIME * POINTS_PER_SEC)

double initT = 0;
double endT = 0;
double frameDur = 0;
double spwnTmr = 0;
double cleanupTmr = 0;
double runTmr = 0;

double frames[RUNNING_TIME * 1000];
uint64_t curFrame = 0;

struct Pt {
	double X; double Y; double Z; double VX; double VY; double VZ; double R; double Life; 
	bool is;
};
struct Pt Pts[MAX_PTS];
int numPts = 0;      
int minPt = 0;       
uint32_t seed = 1234569;

struct Vertex {
	GLfloat pos[3];
	GLfloat normal[3];
};

struct Vertex Vertices[ 24 ];
uint32_t curVertex = 0;
uint32_t curNormal = 0;

void newVertex(x,y,z){
	struct Vertex thisVertex;
	thisVertex.pos[0] = x;
	thisVertex.pos[1] = y;
	thisVertex.pos[2] = z;
	Vertices[curVertex] = thisVertex;
	curVertex++;
}

void newNormal(nx,ny,nz){
	for (int i = curNormal*4; i < (curNormal+1)*4; i++){
		Vertices[i].normal[0] = nx;
		Vertices[i].normal[1] = ny;
		Vertices[i].normal[2] = nz;
	}
	curNormal++;	
}


GLuint gVBO = 0;

double windX = 0; 
double windY = 0;
double windZ = 0;
double grav = 0.5;

float ambient[4] = {0.8, 0.05, 0.1, 1};
float diffuse[4] = {1.0, 1.0, 1.0, 1};
float lightPos[4] = {MIN_X + (MAX_X-MIN_X)/2, MAX_Y, MIN_DEPTH, 0};

uint32_t xorRand() {
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return seed;
}

void movPts(double secs) {
	for (int i = minPt; i <= numPts; i++) {
		if (Pts[i].is == false) {
			continue;
		}
		Pts[i].X += Pts[i].VX * secs;
		Pts[i].Y += Pts[i].VY * secs;
		Pts[i].Z += Pts[i].VZ * secs;
		Pts[i].VX += windX * 1 / Pts[i].R;
		Pts[i].VY += windY * 1 / Pts[i].R;
		Pts[i].VY -= grav;
		Pts[i].VZ += windZ * 1 / Pts[i].R;
		Pts[i].Life -= secs;
		if (Pts[i].Life <= 0) {
			Pts[i].is = false;
		}
	}
}

void spwnPts(double secs) {
	uint32_t num = secs * POINTS_PER_SEC;
	uint32_t i = 0;
	for (; i < num; i++) {
		struct Pt pt;
		pt.X = 0 + (double)(xorRand()%START_RANGE) - START_RANGE/2;
		pt.Y = START_Y;
		pt.Z = START_DEPTH + (double)(xorRand()%START_RANGE) - START_RANGE/2;
		pt.VX = (double)(xorRand() % MAX_INIT_VEL);
		pt.VY = (double)(xorRand() % MAX_INIT_VEL);
		pt.VZ = (double)(xorRand() % MAX_INIT_VEL);
		pt.R = (double)(xorRand() % (MAX_SCALE*100)) / 200;
		pt.Life = (double)(xorRand() % MAX_LIFE) / 1000;
		pt.is = true;
		Pts[numPts] = pt;
		numPts++;
	}
}

void doWind() {
	windX += ( (double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
	windY += ( (double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
	windZ += ( (double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
	if (fabs(windX) > MAX_WIND) {
		windX *= -0.5;
	}
	if (fabs(windY) > MAX_WIND) {
		windY *= -0.5;
	}
	if (fabs(windZ) > MAX_WIND) {
		windZ *= -0.5;
	}
}

void checkColls() {
	for (int i = minPt; i <= numPts; i++) {
		if (Pts[i].is == false) {
			continue;
		}
		if (Pts[i].X < MIN_X) {
			Pts[i].X = MIN_X + Pts[i].R;
			Pts[i].VX *= -1.1; // These particles are magic; they accelerate by 10% at every bounce off the bounding box
		}
		if (Pts[i].X > MAX_X) {
			Pts[i].X = MAX_X - Pts[i].R;
			Pts[i].VX *= -1.1;
		}
		if (Pts[i].Y < MIN_Y) {
			Pts[i].Y = MIN_Y + Pts[i].R;
			Pts[i].VY *= -1.1;
		}
		if (Pts[i].Y > MAX_Y) {
			Pts[i].Y = MAX_Y - Pts[i].R;
			Pts[i].VY *= -1.1;
		}
		if (Pts[i].Z < MIN_DEPTH) {
			Pts[i].Z = MIN_DEPTH + Pts[i].R;
			Pts[i].VZ *= -1.1;
		}
		if (Pts[i].Z > MAX_DEPTH) {
			Pts[i].Z = MAX_DEPTH - Pts[i].R;
			Pts[i].VZ *= -1.1;
		}
	}
}

void cleanupPtPool() {
	for (int i = 0; i <= numPts; i++) {
		if (Pts[i].is == true) {
			minPt += i;
			break;
		}
	}
}


void initScene() {
	glEnable(GL_DEPTH_TEST);
	glEnable(GL_LIGHTING);

	glClearColor(0.1, 0.1, 0.6, 1.0);
	glClearDepth(1);
	glDepthFunc(GL_LEQUAL);

	glLightfv(GL_LIGHT0, GL_AMBIENT, ambient);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, diffuse);
	glLightfv(GL_LIGHT0, GL_POSITION, lightPos);
	glEnable(GL_LIGHT0);

	glViewport(0, 0, WIDTH, HEIGHT);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glFrustum(-1, 1, -1, 1, 1.0, 1000.0);
	glRotatef(20, 1, 0, 0);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	glPushMatrix();

	return;
}

bool loadCubeToGPU(){
	newVertex(-1, -1, 1);
	newVertex(1, -1, 1);
	newVertex(1, 1, 1);
	newVertex(-1, 1, 1);
	newNormal(0, 0, 1);

	newVertex(-1, -1, -1);
	newVertex(-1, 1, -1);
	newVertex(1, 1, -1);
	newVertex(1, -1, -1);
	newNormal(0, 0, -1);

	newVertex(-1, 1, -1);
	newVertex(-1, 1, 1);
	newVertex(1, 1, 1);
	newVertex(1, 1, -1);
	newNormal(0, 1, 0);

	newVertex(-1, -1, -1);
	newVertex(1, -1, -1);
	newVertex(1, -1, 1);
	newVertex(-1, -1, 1);
	newNormal(0, -1, 0);

	newVertex(1, -1, -1);
	newVertex(1, 1, -1);
	newVertex(1, 1, 1);
	newVertex(1, -1, 1);
	newNormal(1, 0, 0);

	newVertex(-1, -1, -1);
	newVertex(-1, -1, 1);
	newVertex(-1, 1, 1);
	newVertex(-1, 1, -1);
	newNormal(-1, 0, 0);

	glGenBuffers( 1, &gVBO );
	glBindBuffer( GL_ARRAY_BUFFER, gVBO );
	glBufferData( GL_ARRAY_BUFFER, 24 * sizeof(struct Vertex), Vertices, GL_STATIC_DRAW );

	return true;
}

void renderPts(){
	glEnableClientState( GL_VERTEX_ARRAY );
	glEnableClientState( GL_NORMAL_ARRAY );	
	glVertexPointer( 3, GL_FLOAT, 24, NULL );	
	glNormalPointer( GL_FLOAT, 12, 0);	

	for (int i = minPt; i <= numPts; i++) {
		if (Pts[i].is == false) {
			continue;
		}
		struct Pt *pt = &Pts[i];
		glMatrixMode(GL_MODELVIEW);
		glPopMatrix();
		glPushMatrix();
		glTranslatef(pt->X, pt->Y, -pt->Z);
		glScalef(pt->R * 2, pt->R*2, pt->R*2);
		glColor4f(0.7, 0.9, 0.2, 1);
		glDrawArrays( GL_QUADS, 0, 24 );
		
	}
	glDisableClientState( GL_NORMAL_ARRAY );
	glDisableClientState( GL_VERTEX_ARRAY );
}

void error_callback(int error, const char* description){
	fputs(description, stderr);
}

int main(int argc, char* argv[]) {
	glfwSetErrorCallback(error_callback);
	if( !glfwInit() ){
		exit(EXIT_FAILURE);
	}
	glfwWindowHint(GLFW_SAMPLES, 2);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
	GLFWwindow* window = glfwCreateWindow(WIDTH, HEIGHT, TITLE, NULL, NULL); 
	if (!window){
		glfwTerminate();
		exit(EXIT_FAILURE);
	}
	glfwMakeContextCurrent(window);
	glfwSwapInterval(1);
	initScene();
	GLenum glewError = glewInit();
	if( glewError != GLEW_OK ){
		printf( "Error initializing GLEW! %s\n", glewGetErrorString( glewError ) );
		return false;
	}
	if( !GLEW_VERSION_2_1 ){
		printf( "OpenGL 2.1 not supported!\n" );
		return false;
	}
	loadCubeToGPU();
	while (!glfwWindowShouldClose(window)){
		initT = glfwGetTime();
		movPts(frameDur);
		doWind();
		if (spwnTmr >= SPAWN_INTERVAL) {
			spwnPts(SPAWN_INTERVAL);
			spwnTmr -= SPAWN_INTERVAL;
		}
		if (cleanupTmr >= (double)MAX_LIFE/1000) {
			cleanupPtPool();
			cleanupTmr = 0;
		}
		checkColls();
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		renderPts();

		glfwSwapBuffers(window);
		glfwPollEvents();

		endT = glfwGetTime();
		frameDur = endT-initT; 
		spwnTmr += frameDur;
		cleanupTmr += frameDur;
		runTmr += frameDur;
		if (runTmr > MAX_LIFE/1000) { 
			frames[curFrame] = frameDur;
			curFrame += 1;			
		}
		
		if (runTmr >= RUNNING_TIME) {
			double sum = 0;
			uint64_t i = 0;
			for (i = 0; i < curFrame; i++) {
				sum += frames[i];
			}
			double mean = sum / (double)curFrame;
			printf("Average framerate was: %f frames per second.\n", 1/mean);		
			double sumDiffs = 0.0;
			for (i = 0; i < curFrame; i++) {
				sumDiffs += pow((1/frames[i])-(1/mean), 2);
			}
			double variance = sumDiffs/ (double)curFrame;
			double sd = sqrt(variance);
			printf("The standard deviation was: %f frames per second.\n", sd);
			break;
		}
	}
	glfwDestroyWindow(window);
	glfwTerminate();
	exit(EXIT_SUCCESS);
}
