import opengl, glfw/glfw, math, unsigned, strutils

from glfw/wrapper import getTime

type
  TPt = object
    x, y, z, vx, vy, vz, r, life: float64
    bis: bool

  TVertex = object
    pos: array[3, GLfloat]
    normal: array[3, GLfloat]
  
  TcoordinateInt = tuple
    x, y, z: int
  
  TcoordinateF64= tuple
    x, y, z: float64
  
  TcoordinateGLfloat = tuple
    x, y, z: GLfloat
  
  Dim = enum
    x, y, z


const
  PrintFrames = true
  Title = "ParticleBench"
  Width = 800
  Height = 600
  Min: TcoordinateInt = (x: -80, y: -90, z: 50)
  Max: TcoordinateInt = (x: 80, y: 50, z: 250)
  StartRange = 15
  StartY = MaxY
  StartDepth = (Min.z + (Min.z+Max.z)/2)
  PointsPerSec = 2000
  MaxInitVel = 7
  MaxLife = 5000
  MaxScale = 4
  WindChange = 2000
  MaxWind = 3
  SpawnInterval = 0.01
  RunningTime = ((MaxLife div 1000) * 5)
  MaxPts = RunningTime * PointsPerSec
  NumVertices = 24

var
  initT = 0.0
  endT = 0.0
  gpuInitT = 0.0
  gpuEndT = 0.0
  frameDur = 0.0
  spwnTmr = 0.0
  cleanupTmr = 0.0
  runTmr = 0.0

  frames: array[RunningTime * 1000, float64]
  gpuTimes: array[RunningTime * 1000, float64]
  curFrame = 0

  pts: array[MaxPts, TPt]
  vertices: array[NumVertices, TVertex]

  numPts = 0
  minPt = 0

  seed = 1234569'u32
  curVertex = 0
  curNormal = 0

  gVBO: GLuint = 0
  wind: TcoordinateF64 = (x: 0.0'f64, y: 0.0'f64, z: 0.0'f64)
  gravity = 0.0'f64
  
  ambient = [Glfloat(0.8), 0.05, 0.1, 1.0]
  diffuse = [Glfloat(1.0), 1.0, 1.0, 1.0]
  lightPos = [GlFloat(Min.x + (Max.x-Min.x)/2), MaxY, Min.z, 0]

proc newVertex(x, y, z: GLfloat) =
  var thisVertex: TVertex
  thisVertex.pos[0] = x
  thisVertex.pos[1] = y
  thisVertex.pos[2] = z
  vertices[curVertex] = thisVertex
  curVertex.inc

proc newNormal(nx, ny, nz: GLfloat) =
  for i in curNormal * 4 .. <((curNormal + 1) * 4):
    vertices[i].normal[0] = nx
    vertices[i].normal[1] = ny
    vertices[i].normal[2] = nz
  curNormal.inc

proc xorRand: uint32 =
  seed = seed xor (seed shl 13)
  seed = seed xor (seed shr 17)
  seed = seed xor (seed shl 5)
  return seed

proc movePts(secs: float64) =
  for i in minPt .. numPts:
    if not pts[i].bis:
      continue
    pts[i].x += pts[i].vx * secs
    pts[i].y += pts[i].vy * secs
    pts[i].z += pts[i].vz * secs
    pts[i].vx += wind.x * 1 / pts[i].r
    pts[i].vy += wind.y * 1 / pts[i].r
    pts[i].vy -= gravity
    pts[i].vz += wind.z * 1 / pts[i].r
    pts[i].life -= secs
    if pts[i].life <= 0:
      pts[i].bis = false

proc spawnPts(secs: float64) =
  let num = secs * PointsPerSec
  for i in 0 .. <num.int:
    var pt = TPt(
      x: 0 + float64(xorRand() mod START_RANGE) - START_RANGE/2,
      y: startY,
      z: startDepth + float64(xorRand() mod START_RANGE) - START_RANGE/2,
      vx: float64(xorRand() mod MaxInitVel),
      vy: float64(xorRand() mod MaxInitVel),
      vz: float64(xorRand() mod MaxInitVel),
      r: float64(xorRand() mod (MAX_SCALE*100)) / 200,
      life: float64(xorRand() mod MaxLife) / 1000,
      bis: true
    )
    pts[numPts] = pt
    numPts.inc

proc doWind() =
  for w in wind.fields:
    w += (float64(xorRand() mod WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur
    if abs(w) > MAX_WIND:
      w *= -0.5

proc checkColls() =
  for i in minPt .. numPts:
    if not pts[i].bis:
      continue
    
    if Pts[i].X < Min.x:
      Pts[i].X = Min.x + Pts[i].R
      Pts[i].VX *= -1.1 # These particles are magic; they accelerate by 10% at every bounce off the bounding box
    
    if Pts[i].X > Max.x:
      Pts[i].X = Max.x - Pts[i].R
      Pts[i].VX *= -1.1
    
    if Pts[i].Y < Min.y:
      Pts[i].Y = Min.y + Pts[i].R
      Pts[i].VY *= -1.1
    
    if Pts[i].Y > MAX_Y:
      Pts[i].Y = MAX_Y - Pts[i].R
      Pts[i].VY *= -1.1
    
    if Pts[i].Z < Min.z:
      Pts[i].Z = Min.z + Pts[i].R
      Pts[i].VZ *= -1.1
    
    if Pts[i].Z > Max.z:
      Pts[i].Z = Max.z - Pts[i].R
      Pts[i].VZ *= -1.1

proc cleanupPtPool =
  for i in minPt .. numPts:
    if Pts[i].bis:
      minPt = i
      break

proc initScene =
  glEnable(GL_DEPTH_TEST)
  glEnable(GL_LIGHTING)

  glClearColor(0.1, 0.1, 0.6, 1.0)
  glClearDepth(1)
  glDepthFunc(GL_LEQUAL)

  glLightfv(GL_LIGHT0, GL_AMBIENT, addr ambient[0])
  glLightfv(GL_LIGHT0, GL_DIFFUSE, addr diffuse[0])
  glLightfv(GL_LIGHT0, GL_POSITION, addr lightPos[0])
  glEnable(GL_LIGHT0)

  glViewport(0, 0, WIDTH, HEIGHT)
  glMatrixMode(GL_PROJECTION)
  glLoadIdentity()
  glFrustum(-1, 1, -1, 1, 1.0, 1000.0)
  glRotatef(20, 1, 0, 0)
  glMatrixMode(GL_MODELVIEW)
  glLoadIdentity()
  glPushMatrix()

template offsetof(typ, field): expr = (var dummy: typ; cast[int](addr(dummy.field)) - cast[int](addr(dummy)))

proc loadCubeToGPU: bool =
  newVertex(-1, -1, 1)
  newVertex(1, -1, 1)
  newVertex(1, 1, 1)
  newVertex(-1, 1, 1)
  newNormal(0, 0, 1)

  newVertex(-1, -1, -1)
  newVertex(-1, 1, -1)
  newVertex(1, 1, -1)
  newVertex(1, -1, -1)
  newNormal(0, 0, -1)

  newVertex(-1, 1, -1)
  newVertex(-1, 1, 1)
  newVertex(1, 1, 1)
  newVertex(1, 1, -1)
  newNormal(0, 1, 0)

  newVertex(-1, -1, -1)
  newVertex(1, -1, -1)
  newVertex(1, -1, 1)
  newVertex(-1, -1, 1)
  newNormal(0, -1, 0)

  newVertex(1, -1, -1)
  newVertex(1, 1, -1)
  newVertex(1, 1, 1)
  newVertex(1, -1, 1)
  newNormal(1, 0, 0)

  newVertex(-1, -1, -1)
  newVertex(-1, -1, 1)
  newVertex(-1, 1, 1)
  newVertex(-1, 1, -1)
  newNormal(-1, 0, 0)

  glGenBuffers(1, addr gVBO)
  glBindBuffer(GL_ARRAY_BUFFER, gVBO)
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(NUM_VERTICES * sizeof(TVertex)), addr vertices[0], GL_STATIC_DRAW)

  glEnableClientState(GL_VERTEX_ARRAY)
  glEnableClientState(GL_NORMAL_ARRAY)

  glVertexPointer(3, cGL_FLOAT, sizeof(TVertex).glsizei, nil)        
  glNormalPointer(cGL_FLOAT, sizeof(TVertex).glsizei, cast[pglvoid](offsetof(TVertex, normal)))        

  return true

proc cleanupBuffers =
  glDeleteBuffers( 1, addr gVBO)
  glDisableClientState( GL_NORMAL_ARRAY )
  glDisableClientState( GL_VERTEX_ARRAY )

proc renderPts =
  for i in minPt .. numPts:
    if (Pts[i].bis == false):
      continue
    
    var pt: ptr TPt = addr pts[i]
    glMatrixMode(GL_MODELVIEW)
    glPopMatrix()
    glPushMatrix()
    glTranslatef(pt.X, pt.Y, -(pt.Z))
    glScalef(pt.R * 2, pt.R * 2, pt.R * 2)
    glColor4f(0.7, 0.9, 0.2, 1)
    glDrawArrays(GL_QUADS, 0, NUM_VERTICES)

when isMainModule:
  init()
  var window = newWnd((Width.positive, Height.positive), Title,
    hints=initHints(nMultiSamples=2, GL_API=initGL_API(version=glv21)))
  window.makeContextCurrent()
  swapInterval(0)
  loadExtensions()
  initScene()
  
  discard loadCubeToGPU()
  while not shouldClose(window):
    initT = getTime()
    movePts(frameDur)
    doWind()
    if (spwnTmr >= SPAWN_INTERVAL):
      spawnPts(SPAWN_INTERVAL)
      spwnTmr -= SPAWN_INTERVAL

    if (cleanupTmr >= MAX_LIFE/1000):
      cleanupPtPool()
      cleanupTmr = 0
    
    checkColls()
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    gpuInitT = getTime()
    renderPts()

    window.swapBufs()
    gpuEndT = getTime()
    pollEvents()

    endT = getTime()
    frameDur = endT-initT
    spwnTmr += frameDur
    cleanupTmr += frameDur
    runTmr += frameDur
    if (runTmr > MAX_LIFE/1000):
      frames[curFrame] = frameDur
      gpuTimes[curFrame] = gpuEndT - gpuInitT
      curFrame += 1
    
    if (runTmr >= RUNNING_TIME):
      var sum = 0'f64
      for i in 0 .. <curFrame:
        sum += frames[i]
      
      var frameTimeMean = sum / curFrame.float64
      echo("Average framerate was: $1 frames per second." % (1/frameTimeMean).formatFloat)
      
      sum = 0
      for i in 0 .. <curFrame:
        sum += gpuTimes[i]
      var gpuTimeMean = sum / curFrame.float64
      echo("Average cpu time was: $1 seconds per frame." %
           formatFloat(frameTimeMean - gpuTimeMean))
      
      var sumDiffs = 0.0
      for i in 0 .. <curFrame:
        sumDiffs += pow((1/frames[i])-(1/frameTimeMean), 2)
      
      var variance = sumDiffs / curFrame.float64
      var sd = sqrt(variance)
      echo("The standard deviation was: $1 frames per second." % sd.formatFloat)
      when PRINT_FRAMES:
        stdout.write("--:")
        for i in 0 .. <curFrame:
          stdout.write(formatFloat(1/frames[i], precision=6))
          stdout.write(",")
        
        stdout.write(".--") 

      break
    
  cleanupBuffers()
  window.destroy()
  terminate()


