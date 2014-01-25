import std.stdio;
import std.math;
import derelict.glfw3.glfw3;
import derelict.opengl3.gl;

enum { 
	PRINT_FRAMES = true,
	TITLE = "ParticleBench",
	WIDTH = 800,
	HEIGHT = 600,

	MIN_X = -80,
	MAX_X = 80,
	MIN_Y = -90,
	MAX_Y = 50,
	MIN_DEPTH = 50,
	MAX_DEPTH = 250,

	START_RANGE = 15,
	START_X = (MIN_X + (MIN_X + MAX_X) / 2),
	START_Y = MAX_Y,
	START_DEPTH = (MIN_DEPTH + (MIN_DEPTH + MAX_DEPTH) / 2),

	POINTS_PER_SEC = 2000,
	MAX_INIT_VEL = 7,
	SPAWN_INTERVAL = 0.01,
	MAX_LIFE = 5000,
	MAX_SCALE = 4,

	WIND_CHANGE = 2000,
	MAX_WIND = 3,
	RUNNING_TIME = ((MAX_LIFE / 1000) * 4),
	MAX_PTS = (RUNNING_TIME * POINTS_PER_SEC)
}

float[4] ambient = [0.8, 0.05, 0.1, 1];
float[4] diffuse = [1.0, 1.0, 1.0, 1];
float[4] lightPos = [MIN_X + (MAX_X - MIN_X) / 2, MAX_Y, MIN_DEPTH, 0];

GLuint gVBO = 0;

double
	windX = 0, 
	windY = 0,
	windZ = 0,
	grav = 50,

	initT = 0,
	endT = 0,
	gpuInitT = 0,
	gpuEndT = 0,
	frameDur = 0,
	spwnTmr = 0,
	cleanupTmr = 0,
	runTmr = 0;

double[RUNNING_TIME * 1000] 
	frames,
	gpuTimes;

uint curFrame = 0;

struct Pt {
	double X; double Y; double Z; double VX; double VY; double VZ; double R; double Life; 
	bool alive;
};
Pt[MAX_PTS] Pts;
int
	numPts = 0,      
	minPt = 0;
       
uint seed = 1234569;

struct Vertex {
	GLfloat pos[3];
	GLfloat normal[3];
};

Vertex[24] Vertices = void;
uint
	curVertex = 0,
	curNormalX = 0,
	curNormalY = 0,
	curNormalZ = 0;

void newVertex(int x,int y,int z){
	Vertex thisVertex;
	thisVertex.pos[0] = x;
	thisVertex.pos[1] = y;
	thisVertex.pos[2] = z;

	thisVertex.normal[0] = curNormalX;
	thisVertex.normal[1] = curNormalY;
	thisVertex.normal[2] = curNormalZ;

	Vertices[curVertex] = thisVertex;
	curVertex++;
}

void newNormal(int nx,int ny,int nz){
	curNormalX = nx;
	curNormalY = ny;
	curNormalZ = nz;
}

bool loadCubeToGPU(){
	newNormal(0, 0, 1);
	newVertex(-1, -1, 1);
	newVertex(1, -1, 1);
	newVertex(1, 1, 1);
	newVertex(-1, 1, 1);

	newNormal(0, 0, -1);
	newVertex(-1, -1, -1);
	newVertex(-1, 1, -1);
	newVertex(1, 1, -1);
	newVertex(1, -1, -1);

	newNormal(0, 1, 0);
	newVertex(-1, 1, -1);
	newVertex(-1, 1, 1);
	newVertex(1, 1, 1);
	newVertex(1, 1, -1);

	newNormal(0, -1, 0);
	newVertex(-1, -1, -1);
	newVertex(1, -1, -1);
	newVertex(1, -1, 1);
	newVertex(-1, -1, 1);

	newNormal(1, 0, 0);
	newVertex(1, -1, -1);
	newVertex(1, 1, -1);
	newVertex(1, 1, 1);
	newVertex(1, -1, 1);

	newNormal(-1, 0, 0);
	newVertex(-1, -1, -1);
	newVertex(-1, -1, 1);
	newVertex(-1, 1, 1);
	newVertex(-1, 1, -1);

	glGenBuffers( 1, &gVBO);
	glBindBuffer( GL_ARRAY_BUFFER, gVBO);
	glBufferData( GL_ARRAY_BUFFER, 24 * Vertex.sizeof, Vertices.ptr, GL_STATIC_DRAW);

	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);	
	glVertexPointer(3, GL_FLOAT, 24, null);	
	glNormalPointer(GL_FLOAT, Vertex.sizeof, cast(void*)(Vertex.normal.offsetof));	
	glMatrixMode(GL_MODELVIEW);

	return true;
}

uint xorRand() {
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return seed;
}

void movPts(double secs) {
	foreach (i; minPt .. numPts){
		if (Pts[i].alive == false) {
			continue;
		}
		Pts[i].X += Pts[i].VX * secs;
		Pts[i].Y += Pts[i].VY * secs;
		Pts[i].Z += Pts[i].VZ * secs;
		Pts[i].VX += windX * 1 / Pts[i].R;
		Pts[i].VY += windY * 1 / Pts[i].R;
		Pts[i].VY -= grav * secs;
		Pts[i].VZ += windZ * 1 / Pts[i].R;
		Pts[i].Life -= secs;
		if (Pts[i].Life <= 0) {
			Pts[i].alive = false;
		}
	}
}

void spwnPts(double secs) {
	uint num = cast(int)(secs * POINTS_PER_SEC);
	uint i = 0;
	for (; i < num; i++) {
		Pt pt;
		pt.X = 0 + cast(double)(xorRand() % START_RANGE) - START_RANGE / 2;
		pt.Y = START_Y;
		pt.Z = START_DEPTH + cast(double)(xorRand() % START_RANGE) - START_RANGE / 2;
		pt.VX = cast(double)(xorRand() % MAX_INIT_VEL);
		pt.VY = cast(double)(xorRand() % MAX_INIT_VEL);
		pt.VZ = cast(double)(xorRand() % MAX_INIT_VEL);
		pt.R = cast(double)(xorRand() % (MAX_SCALE * 100)) / 200;
		pt.Life = cast(double)(xorRand() % MAX_LIFE) / 1000;
		pt.alive = true;
		Pts[numPts] = pt;
		numPts++;
	}
}

void doWind() {
	windX += ( cast(double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE / 2000) * frameDur;
	windY += ( cast(double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE / 2000) * frameDur;
	windZ += ( cast(double)(xorRand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE / 2000) * frameDur;
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
	foreach (i; minPt .. numPts){
		if (Pts[i].alive == false) {
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
	foreach (i; minPt .. numPts){
		if (Pts[i].alive == true) {
			minPt = i;
			break;
		}
	}
}

void main() {
	DerelictGL.load();	
	DerelictGLFW3.load();
	glfwInit();
	glfwWindowHint(GLFW_SAMPLES, 2);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
	GLFWwindow* window = glfwCreateWindow(WIDTH, HEIGHT, TITLE, null, null); 
	glfwMakeContextCurrent(window);
	glfwSwapInterval(0);
	DerelictGL.reload();
	
	initScene();
	loadCubeToGPU();
	while (!glfwWindowShouldClose(window)){
		initT = glfwGetTime();
		if (spwnTmr >= SPAWN_INTERVAL) {
			spwnPts(SPAWN_INTERVAL);
			spwnTmr -= SPAWN_INTERVAL;
		}
		if (cleanupTmr >= cast(double)(MAX_LIFE) / 1000) {
			cleanupPtPool();
			cleanupTmr = 0;
		}
		doWind();
		checkColls();
		movPts(frameDur);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		gpuInitT = glfwGetTime();
		renderPts();
		glfwSwapBuffers(window);
		gpuEndT = glfwGetTime();
		glfwPollEvents();

		endT = glfwGetTime();
		frameDur = endT-initT; 
		spwnTmr += frameDur;
		cleanupTmr += frameDur;
		runTmr += frameDur;
		if (runTmr > MAX_LIFE / 1000) { 
			frames[curFrame] = frameDur;
                	gpuTimes[curFrame] = gpuEndT - gpuInitT;
			curFrame += 1;			
		}
		
		if (runTmr >= RUNNING_TIME) {
			double sum = 0;
			foreach (i; 0 .. curFrame){
				sum += frames[i];
			}
			double frameTimeMean = sum / cast(double)curFrame;
			printf("Average framerate was: %f frames per second.\n", 1 / frameTimeMean);

			sum = 0;
			foreach (i; 0 .. curFrame){
				sum += gpuTimes[i];
			}
			double gpuTimeMean = sum / cast(double)curFrame;
			printf("Average cpu time was- %f seconds per frame.\n", frameTimeMean - gpuTimeMean);

			double sumDiffs = 0.0;
			foreach (i; 0 .. curFrame){
				sumDiffs += pow((1 / frames[i])-(1 / frameTimeMean), 2);
			}
			double variance = sumDiffs/ cast(double)curFrame;
			double sd = sqrt(variance);
			printf("The standard deviation was: %f frames per second.\n", sd);
			if (PRINT_FRAMES == 1){
				printf("--:");
				foreach (i; 0 .. curFrame){
					printf("%f",1 / frames[i]);
					printf(",");
				}
				printf(".--");
			}		

			break;
		} 
	}
	glfwDestroyWindow(window);
	glfwTerminate();
}

void initScene() {
	glEnable(GL_DEPTH_TEST);
	glEnable(GL_LIGHTING);

	glClearColor(0.1, 0.1, 0.6, 1.0);
	glClearDepth(1);
	glDepthFunc(GL_LEQUAL);

	glLightfv(GL_LIGHT0, GL_AMBIENT, (ambient).ptr);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, (diffuse).ptr);
	glLightfv(GL_LIGHT0, GL_POSITION, (lightPos).ptr);
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

void renderPts(){
	foreach (i; minPt .. numPts){	
		if (Pts[i].alive == false) {
			continue;
		}
		Pt *pt = &Pts[i];
		glPopMatrix();
		glPushMatrix();
		glTranslatef(pt.X, pt.Y, -pt.Z);
		glScalef(pt.R * 2, pt.R * 2, pt.R * 2);
		glDrawArrays(GL_QUADS, 0, 24);	
	}
}
