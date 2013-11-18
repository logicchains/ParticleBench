#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

#include <iostream>
#include <string>
#include <vector>
#include <cstdint>
#include <cmath>

#include <GL/glew.h>
#include <GLFW/glfw3.h>

using std::cout;
using std::string;
using std::vector;
using std::endl;

constexpr const char * TITLE = "ParticleBench";
constexpr int32_t WIDTH = 800;
constexpr int32_t HEIGHT = 600;

constexpr int32_t MIN_X = -80;
constexpr int32_t MAX_X = 80;
constexpr int32_t MIN_Y = -90;
constexpr int32_t MAX_Y = 50;
constexpr int32_t MIN_DEPTH = 50;
constexpr int32_t MAX_DEPTH = 250;

constexpr int32_t START_RANGE = 15;
constexpr int32_t START_X = (MIN_X + (MIN_X + MAX_X)/2);
constexpr int32_t START_Y = MAX_Y;
constexpr int32_t START_DEPTH = (MIN_DEPTH + (MIN_DEPTH + MAX_DEPTH) / 2);

constexpr int32_t POINTS_PER_SEC = 2000;
constexpr int32_t MAX_INIT_VEL = 7;
constexpr int32_t MAX_LIFE = 5000;
constexpr int32_t MAX_SCALE = 4;

constexpr int32_t WIND_CHANGE = 2000;
constexpr int32_t MAX_WIND = 3;
constexpr double SPAWN_INTERVAL = 0.01;
constexpr int32_t RUNNING_TIME = ((MAX_LIFE / 1000) * 5);
constexpr int32_t MAX_PTS = (RUNNING_TIME * POINTS_PER_SEC);

constexpr uint32_t NUM_VERTICES = 24;
constexpr uint32_t NUM_NORMALS = NUM_VERTICES / 4;

constexpr uint32_t RAND_SEED = 1234569;

constexpr double WINDX = 0; 
constexpr double WINDY = 0;
constexpr double WINDZ = 0;
constexpr double GRAV = 0.5;

struct Pt {
  double X, Y, Z, VX, VY, VZ, R, Life; 
  bool is;
};

struct Vertex {
  GLfloat pos[3];
  GLfloat normal[3];
};

const GLfloat srcCoords[ NUM_VERTICES ][3] = {
  {-1, -1, 1},
  {1, -1, 1},
  {1, 1, 1},
  {-1, 1, 1},
  {-1, -1, -1},
  {-1, 1, -1},
  {1, 1, -1},
  {1, -1, -1},
  {-1, 1, -1},
  {-1, 1, 1},
  {1, 1, 1},
  {1, 1, -1},
  {-1, -1, -1},
  {1, -1, -1},
  {1, -1, 1},
  {-1, -1, 1},
  {1, -1, -1},
  {1, 1, -1},
  {1, 1, 1},
  {1, -1, 1},
  {-1, -1, -1},
  {-1, -1, 1},
  {-1, 1, 1},
  {-1, 1, -1}
};

const GLfloat srcNormals[ NUM_NORMALS ][3] = {
  {0, 0, 1},
  {0, 0, -1},
  {0, 1, 0},
  {0, -1, 0},
  {1, 0, 0},
  {-1, 0, 0}
};

struct XorRandGenerator {
  uint32_t operator()( uint32_t & gen ) {
    gen ^= gen << 13;
    gen ^= gen >> 17;
    gen ^= gen << 5;
    return gen;
  }

  uint32_t mod( uint32_t & gen, const uint32_t mod ) {
    return ((*this)( gen ))%mod;
  }
};

template<class RandGenerator>
class Particles {
public:
  Particles( RandGenerator & randGenerator, const uint32_t numParticles ) :
    randGenerator_( randGenerator ),
    numPts_( 0 ),
    minPt_( 0 ),
    particles_( numParticles, Pt {0, 0, 0, 0, 0, 0, 0, 0, 0 } ),
    windX_( WINDX ), windY_( WINDY ), windZ_( WINDZ ) {};

  void moveParticles( double secs ) {
    for( uint32_t i = minPt_; i < numPts_; i++) {
      Pt & p( particles_[i] );
      if( p.is == false ) {
	continue;
      }
      p.X += p.VX * secs;
      p.Y += p.VY * secs;
      p.Z += p.VZ * secs;
      p.VX += windX_ * 1 / p.R;
      p.VY += windY_ * 1 / p.R;
      p.VY -= GRAV;
      p.VZ += windZ_ * 1 / p.R;
      p.Life -= secs;
      if (p.Life <= 0 ) {
	p.is = false;
      }
    }
  }

  void doWind( const double frameDur, uint32_t & randValue )
  {
    windX_ += ( (double)( randGenerator_.mod( randValue, WIND_CHANGE ) ) / WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
    windY_ += ( (double)( randGenerator_.mod( randValue, WIND_CHANGE ) ) / WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
    windZ_ += ( (double)( randGenerator_.mod( randValue, WIND_CHANGE ) ) / WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
    if (fabs(windX_) > MAX_WIND) {
      windX_ *= -0.5;
    }
    if (fabs(windY_) > MAX_WIND) {
      windY_ *= -0.5;
    }
    if (fabs(windZ_) > MAX_WIND) {
      windZ_ *= -0.5;
    }
  }

  void spawnParticles(double secs, uint32_t & randValue ) {
    uint32_t num = secs * POINTS_PER_SEC;
    for ( uint32_t i = 0 ; i < num; i++) {
      Pt & pt = particles_[numPts_];
      pt.X = 0 + (double)( randGenerator_.mod( randValue, START_RANGE ) ) - START_RANGE/2;
      pt.Y = START_Y;
      pt.Z = START_DEPTH + (double)( randGenerator_.mod( randValue, START_RANGE ) ) - START_RANGE/2;
      pt.VX = (double)( randGenerator_.mod( randValue, MAX_INIT_VEL) );
      pt.VY = (double)( randGenerator_.mod( randValue, MAX_INIT_VEL) );
      pt.VZ = (double)( randGenerator_.mod( randValue, MAX_INIT_VEL) );
      pt.R = (double)( randGenerator_.mod( randValue, (MAX_SCALE*100) ) ) / 200;
      pt.Life = (double)( randGenerator_.mod( randValue, MAX_LIFE) ) / 1000;
      pt.is = true;
      numPts_++;
    }
  }

  void checkForCollisions() {
    for (int i = minPt_; i < numPts_; i++) {
      Pt & p( particles_[i] );
      if (p.is == false) {
	continue;
      }
      if (p.X < MIN_X) {
	p.X = MIN_X + p.R;
	p.VX *= -1.1; // These particles are magic; they accelerate by 10% at every bounce off the bounding box
      }
      if (p.X > MAX_X) {
	p.X = MAX_X - p.R;
	p.VX *= -1.1;
      }
      if (p.Y < MIN_Y) {
	p.Y = MIN_Y + p.R;
	p.VY *= -1.1;
      }
      if (p.Y > MAX_Y) {
	p.Y = MAX_Y - p.R;
	p.VY *= -1.1;
      }
      if (p.Z < MIN_DEPTH) {
	p.Z = MIN_DEPTH + p.R;
	p.VZ *= -1.1;
      }
      if (p.Z > MAX_DEPTH) {
	p.Z = MAX_DEPTH - p.R;
	p.VZ *= -1.1;
      }
    }
  }

  void renderParticles() {
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    for (int i = minPt_; i < numPts_; i++) {
      Pt & p( particles_[i] );
      if (p.is == false) {
	continue;
      }
      glMatrixMode(GL_MODELVIEW);
      glPopMatrix();
      glPushMatrix();
      glTranslatef(p.X, p.Y, -p.Z);
      glScalef(p.R*2, p.R*2, p.R*2);
      glColor4f(0.7, 0.9, 0.2, 1);
      glDrawArrays( GL_QUADS, 0, 24 );	
    }
  }

  void cleanupPtPool() {
    for (int i = minPt_; i < numPts_; i++) {
      if (particles_[i].is == true) {
	minPt_ = i;
	break;
      }
    }
  }

private:
  int numPts_;
  int minPt_;
  double windX_, windY_, windZ_;
  vector<Pt> particles_;
  RandGenerator & randGenerator_;
};

template<class RandGenerator>
class GLRenderer {
public:
  GLRenderer( uint32_t randSeed ) :
    randValue_( randSeed ),
    gVBO_( 0 ),
    particles_( randGenerator_, MAX_PTS ),
    spwnTmr_( 0.0 ),
    cleanupTmr_( 0.0 ) {
    vertices_.reserve( NUM_VERTICES );
  }

  void initScene() {
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_LIGHTING);

    glClearColor(0.1, 0.1, 0.6, 1.0);
    glClearDepth(1);
    glDepthFunc(GL_LEQUAL);

    float ambient[4] = {0.8, 0.05, 0.1, 1};
    glLightfv(GL_LIGHT0, GL_AMBIENT, ambient);
    float diffuse[4] = {1.0, 1.0, 1.0, 1};
    glLightfv(GL_LIGHT0, GL_DIFFUSE, diffuse);
    float lightPos[4] = {MIN_X + (MAX_X-MIN_X)/2, MAX_Y, MIN_DEPTH, 0};
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
  }

  void setupBuffers() {
    uint32_t curCoord { 0 };
    for( uint32_t n = 0 ; n < NUM_NORMALS ; ++n ) {
      const GLfloat *cn = srcNormals[n];
      for( uint32_t p = 0 ; p < 4 ; ++p, ++curCoord ) {
	const GLfloat *cv = srcCoords[curCoord];
	vertices_.emplace_back( Vertex {{cv[0], cv[1], cv[2] }, {cn[0], cn[1], cn[2]}} );
      }
    }

    glGenBuffers( 1, &gVBO_ );
    glBindBuffer( GL_ARRAY_BUFFER, gVBO_ );
    glBufferData( GL_ARRAY_BUFFER, NUM_VERTICES * sizeof(Vertex), &(vertices_[0]), GL_STATIC_DRAW );

    glEnableClientState( GL_VERTEX_ARRAY );
    glEnableClientState( GL_NORMAL_ARRAY );	

    glVertexPointer( 3, GL_FLOAT, sizeof( Vertex), 0 );
    glNormalPointer( GL_FLOAT, sizeof( Vertex ), (const GLvoid *)offsetof( Vertex, normal ) );
  }

  void teardownBuffers() {
    glDisableClientState( GL_NORMAL_ARRAY );
    glDisableClientState( GL_VERTEX_ARRAY );

    glDeleteBuffers( 1, &gVBO_ );
  }

  void doTimestep( const double frameDuration ) {
    particles_.moveParticles( frameDuration );
    particles_.doWind( frameDuration, randValue_ );
    if( spwnTmr_ >= SPAWN_INTERVAL ) {
      particles_.spawnParticles( SPAWN_INTERVAL, randValue_ );
      spwnTmr_ -= SPAWN_INTERVAL;
    }
    if( cleanupTmr_ >= (MAX_LIFE/1000.0) ) {
      particles_.cleanupPtPool();
      cleanupTmr_ = 0;
    }
    particles_.checkForCollisions();
    particles_.renderParticles();
  }

  void updateTimers( const double frameDuration ) {
    spwnTmr_ += frameDuration;
    cleanupTmr_ += frameDuration;
  }

private:
  RandGenerator randGenerator_;
  uint32_t randValue_;
  vector<Vertex> vertices_;

  GLuint gVBO_;

  Particles<RandGenerator> particles_;

  double spwnTmr_;
  double cleanupTmr_;
};


void error_callback(int error, const char* description) {
  fputs(description, stderr);
  fflush( stderr );
}

int main(int argc, char* argv[]) {
  vector<double> frames( (RUNNING_TIME * 1000), 0.0 );
  uint64_t curFrame( 0 );
  glfwSetErrorCallback(error_callback);
  if( !glfwInit() ) {
    exit(EXIT_FAILURE);
  }
  glfwWindowHint(GLFW_SAMPLES, 2);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
  GLFWwindow* window = glfwCreateWindow(WIDTH, HEIGHT, TITLE, NULL, NULL); 
  if( !window ) {
    glfwTerminate();
    exit(EXIT_FAILURE);
  }
  glfwMakeContextCurrent(window);
  glfwSwapInterval(0);

  GLRenderer<XorRandGenerator> glRenderer( RAND_SEED );
  glRenderer.initScene();

  GLenum glewError = glewInit();
  if( glewError != GLEW_OK ){
    printf( "Error initializing GLEW! %s\n", glewGetErrorString( glewError ) );
    return false;
  }
  if( !GLEW_VERSION_2_1 ){
    printf( "OpenGL 2.1 not supported!\n" );
    return false;
  }
  glRenderer.setupBuffers();

  double initT, endT, frameDur, runTmr = 0;
  while (!glfwWindowShouldClose(window)) {
    initT = glfwGetTime();
    glRenderer.doTimestep( frameDur );
    glfwSwapBuffers(window);
    glfwPollEvents();
    endT = glfwGetTime();
    frameDur = endT-initT;
    glRenderer.updateTimers( frameDur );
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
  glRenderer.teardownBuffers();
  glfwDestroyWindow(window);
  glfwTerminate();
  exit(EXIT_SUCCESS);
}
