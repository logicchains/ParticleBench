from OpenGL.GL import *
from OpenGL.arrays import vbo
from OpenGL.GLUT import *
from OpenGL.GLU import *
#import pygame
#from pygame.locals import *


TITLE = "ParticleBench"
WIDTH = 800
HEIGHT = 600

MIN_X = -80
MAX_X = 80
MIN_Y = -90
MAX_Y = 50
MIN_DEPTH = 50
MAX_DEPTH = 250

START_RANGE = 15
START_X = (MIN_X + (MIN_X+MAX_X)/2)
START_Y = MAX_Y
START_DEPTH = (MIN_DEPTH + (MIN_DEPTH+MAX_DEPTH)/2)

POINTS_PER_SEC = 2000
MAX_INIT_VEL = 7
MAX_LIFE = 5000
MAX_SCALE = 4

WIND_CHANGE = 2000
MAX_WIND = 3
SPAWN_INTERVAL = 0.01 
#RUNNING_TIME = ((MAX_LIFE / 1000) * 5)
RUNNING_TIME = ((5) * 5)
MAX_PTS = (RUNNING_TIME * POINTS_PER_SEC)

ambient = (0.8, 0.05, 0.1, 1)
diffuse = (1.0, 1.0, 1.0, 1)
lightPos = (MIN_X + (MAX_X-MIN_X)/2, MAX_Y, MIN_DEPTH, 0)

initT = 0.0
endT = 0.0
frameDur = 0.0
spwnTmr = 0.0
cleanupTmr = 0.0
runTmr = 0.0

frames = [0.0] * (RUNNING_TIME * 1000)  
curFrame = 0

class Pt():
    def __init__(self, X, Y, Z, VX, VY, VZ, R, Life, Alive):
        self.X = X
        self.Y = Y
        self.Z = Z
        self.VX = VX
        self.VY = VY
        self.VZ = VZ
        self.R = R
        self.Life = Life
        self.Alive = Alive

Pts = [Pt(0,0,0,0,0,0,0,0,0) for _ in range(MAX_PTS)]
maxPt = 0
minPt = 0       
seed = 1234569

gVBO = None

windX = 0 
windY = 0
windZ = 0
grav = 0.5

Vertices = [-1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0,-1.0, 1.0, 1.0, 0.0, 0.0, 1.0, -1.0, -1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 1.0, -1.0, 0.0, 0.0, -1.0, 1.0, 1.0, -1.0, 0.0, 0.0, -1.0, 1.0, -1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 1.0, -1.0, 0.0, 1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, -1.0, 0.0, 1.0, 0.0, -1.0, -1.0, -1.0, 0.0, -1.0, 0.0, 1.0, -1.0, -1.0, 0.0, -1.0, 0.0, 1.0, -1.0, 1.0, 0.0, -1.0, 0.0, -1.0, -1.0, 1.0, 0.0, -1.0, 0.0, 1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 1.0, 1.0, 0.0, 0.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 1.0, -1.0, 0.0, 0.0, -1.0, 1.0, 1.0, -1.0, 0.0, 0.0, -1.0, 1.0, -1.0, -1.0, 0.0, 0.0]

def rand():
	global seed
	seed ^= seed << 13
	seed ^= seed >> 17
	seed ^= seed << 5
	return seed

def movPts(secs):
	for i in range(minPt, maxPt):
		if Pts[i].Alive == 0:
			continue
		Pts[i].X += Pts[i].VX * secs
		Pts[i].Y += Pts[i].VY * secs
		Pts[i].Z += Pts[i].VZ * secs
		Pts[i].VX += windX * 1 / Pts[i].R
		Pts[i].VY += windY * 1 / Pts[i].R
		Pts[i].VY -= grav
		Pts[i].VZ += windZ * 1 / Pts[i].R
		Pts[i].Life -= secs
		if Pts[i].Life <= 0:
			Pts[i].Alive = false

def spwnPts(secs):
	num = secs * POINTS_PER_SEC;
	global Pts
	global numPts
	for i in range(0, num):
		pt = Pt(0 + rand()%START_RANGE - START_RANGE/2, START_Y,START_DEPTH + rand()%START_RANGE - START_RANGE/2, rand() % MAX_INIT_VEL, rand() % MAX_INIT_VEL, rand() % MAX_INIT_VEL, (rand() % (MAX_SCALE * 100)) / 200, (rand() % MAX_LIFE) / 1000, 1)
		Pts[numPts] = pt
		numPts+=1

def doWind():
	global windX
	global windY
	global windZ
	windX += ( (rand % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur
	windY += ( (rand % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur
	windZ += ( (rand % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur
	if (math.fabs(windX) > MAX_WIND):
		windX *= -0.5
	if (math.fabs(windY) > MAX_WIND):
		windY *= -0.5
	if (math.fabs(windZ) > MAX_WIND):
		windZ *= -0.5

def checkColls():
	for i in range(minPt, maxPt):
		if (Pts[i].Alive == false):
			continue
		if (Pts[i].X < MIN_X):
			Pts[i].X = MIN_X + Pts[i].R
			Pts[i].VX *= -1.1
		if (Pts[i].X > MAX_X):
			Pts[i].X = MAX_X - Pts[i].R
			Pts[i].VX *= -1.1
		if (Pts[i].Y < MIN_Y):
			Pts[i].Y = MIN_Y + Pts[i].R
			Pts[i].VY *= -1.1
		if (Pts[i].Y > MAX_Y):
			Pts[i].Y = MAX_Y - Pts[i].R
			Pts[i].VY *= -1.1
		if (Pts[i].Z < MIN_DEPTH):
			Pts[i].Z = MIN_DEPTH + Pts[i].R
			Pts[i].VZ *= -1.1
		if (Pts[i].Z > MAX_DEPTH):
			Pts[i].Z = MAX_DEPTH - Pts[i].R
			Pts[i].VZ *= -1.1

def cleanupPtPool():
	global minPt
	for i in range(minPt, maxPt):
		if (Pts[i].Alive == true):
			minPt = i
			break
def initScene():
	glEnable(GL_DEPTH_TEST)
	glEnable(GL_LIGHTING)

	glClearColor(0.1, 0.1, 0.6, 1.0)
	glClearDepth(1)
	glDepthFunc(GL_LEQUAL)

	glLightfv(GL_LIGHT0, GL_AMBIENT, ambient)
	glLightfv(GL_LIGHT0, GL_DIFFUSE, diffuse)
	glLightfv(GL_LIGHT0, GL_POSITION, lightPos)
	glEnable(GL_LIGHT0)

	glViewport(0, 0, WIDTH, HEIGHT)
	glMatrixMode(GL_PROJECTION)
	glLoadIdentity()
	glFrustum(-1, 1, -1, 1, 1.0, 1000.0)
	glRotatef(20, 1, 0, 0)
	glMatrixMode(GL_MODELVIEW)
	glLoadIdentity()
	glPushMatrix()

	global gVBO
	glGenBuffers(1)
#	glBindBuffer( GL_ARRAY_BUFFER, gVBO );
#	glBufferData( GL_ARRAY_BUFFER, len(Vertices) * sizeOfFloat, array_type(*Vertices), GL_STATIC_DRAW )

#	glEnableClientState( GL_VERTEX_ARRAY )
#	glEnableClientState( GL_NORMAL_ARRAY )	
#	glVertexPointer( 3, GL_FLOAT, 24, null )	
#	glNormalPointer( GL_FLOAT, 12, 0)
#	glMatrixMode(GL_MODELVIEW)

SCREEN_SIZE = (800, 600)    

if __name__ == '__main__':
	glutInit()
	glutInitWindowSize(WIDTH,HEIGHT)
	glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA)
	glutCreateWindow(TITLE)
#	glutDisplayFunc(mainLoop)

#	pygame.init()
#	screen = pygame.display.set_mode(SCREEN_SIZE, HWSURFACE|OPENGL|DOUBLEBUF)
#	resize(*SCREEN_SIZE)

	initScene()
	glutMainLoop()
