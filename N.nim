import opengl, glfw/glfw, math, unsigned, strutils

from glfw/wrapper import getTime

type
  TCoord = enum
    x, y, z

  TPt = object                       # A particle object:
    p, v : array[TCoord, float64]  # The position and velocity. 
    r, life: float64                 # Radius and remaining lifetime
    bis: bool                        # Living or not

  TVertex = object
    pos: array[TCoord, GLfloat]
    normal: array[TCoord, GLfloat]

const
  PrintFrames = true
  Title = "ParticleBench"
  Width = 800
  Height = 600

  MaxLife = 5000                        # Maximum particle lifetime in milliseconds
  PointsPerSec = 2000                   # Particles created per second  
  RunningTime = (MaxLife div 1000) * 5  # The total running time of the animation, in ms
  MaxPts = RunningTime * PointsPerSec   # The size of the particle pool
  MaxInitVel = 7                        # The maximum initial speed of a newly created
  MaxScale = 4                          # The maximum scale of a particle

  Min: array[TCoord, float] = [-80.0, -90.0, 50.0]  # Array[x, y, z]. 
  Max: array[TCoord, float] = [80.0, 50.0, 250.0]   # The Y axis is height, the Z axis is depth
  
  StartRange = 15  # Twice the maximum distance a particle may be spawned from the start point
  StartY = Max[y]
  StartDepth = (Min[z] + (Min[z]+Max[z])/2)
 
  WindChange = 2000                     # The maximum change in windspeed per second, in milliseconds
  MaxWind = 3                           # Maximum windspeed in seconds before wind is reversed at half speed
  SpawnInterval = 0.01                  # How often particles are spawned, in seconds
  NumVertices = 24

var
  ambient = [Glfloat(0.8), 0.05, 0.1, 1.0]
  diffuse = [Glfloat(1.0), 1.0, 1.0, 1.0]
  lightPos = [GlFloat(Min[x] + (Max[x]-Min[x])/2), 
              Max[y], Min[z], 0]
              
  vertices: array[NumVertices, TVertex]  
  wind: array[TCoord, float64] = [0.0, 0.0, 0.0]  # Wind speed. 
  gravity = 0.5'f64
  gVBO: GLuint = 0
   
type TPts = object
  low, high: int            # The index range in the pool that currently contains a particle
  pool: array[MaxPts, TPt]  # The pool of particles
  
proc `[]`(pts: var Tpts, key: int): var TPt = pts.pool[key]
proc `[]=`(pts: var Tpts, key: int, val: TPt) = pts.pool[key] = val

proc toGlVec(a: Array[3, int]) : array[TCoord, GLfloat] = 
  return [GlFloat(a[x.ord]), GlFloat(a[y.ord]), GlFloat(a[z.ord])]

proc newVertexGroup(normal: Array[3, int], pos: varargs[Array[3, int]]) =
  var curVertex {.global.} = 0
  for p in pos:
    vertices[curVertex] = TVertex(pos: toGlVec(p),normal: toGlVec(normal))
    curVertex.inc

proc xorRand: uint32 =
  var seed {.global.} = 1234569'u32  # Initial PRNG seed, reused as state.
  seed = seed xor (seed shl 13)
  seed = seed xor (seed shr 17)
  seed = seed xor (seed shl 5)
  return seed

proc move(pts: var TPts, secs, gravity: float64) =
  for i in pts.low .. pts.high:
    if not pts[i].bis:
      continue
    for c in TCoord:
      {.unroll: 3.}
      pts[i].p[c] += pts[i].v[c] * secs
      pts[i].v[c] += wind[c] * 1 / pts[i].r  # The effect of the wind on a particle is 
    pts[i].v[y] -= gravity                           # inversely proportional to its radius.
    pts[i].life -= secs
    
    if pts[i].life <= 0:
      pts[i].bis = false
      
proc spawn(pts: var TPts, secs: float64) =
  let num = secs * PointsPerSec
  for i in 0 .. <num.int:
    pts[pts.high] = TPt(
      p: [0 + float64(xorRand() mod START_RANGE) - START_RANGE/2,
        startY,
        startDepth + float64(xorRand() mod START_RANGE) - START_RANGE/2],
      v: [float64(xorRand() mod MaxInitVel),
        float64(xorRand() mod MaxInitVel),
        float64(xorRand() mod MaxInitVel)],
      r: float64(xorRand() mod (MAX_SCALE*100)) / 200,
      life: float64(xorRand() mod MaxLife) / 1000,
      bis: true
    )
    pts.high.inc

proc doWind(secs: float64) =
  for c in TCoord:
    wind[c] += (float64(xorRand() mod WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * secs
    if abs(wind[c]) > MAX_WIND:
      wind[c] *= -0.5

proc checkColls(pts: var TPts) =
  for i in pts.low .. pts.high:
    if not pts[i].bis:
      continue
    for c in TCoord:
      {.unroll: 3.}
      if pts[i].p[c] < Min[c]:
        pts[i].p[c] = Min[c] + pts[i].r
        pts[i].v[c] *= -1.1  # These particles are magic; 
                             # they accelerate by 10% at every bounce off the bounding box
      if pts[i].p[c] > Max[c]:
        pts[i].p[c] = Max[c] - pts[i].r
        pts[i].v[c] *= -1.1

proc cleanupPtPool(pts: var TPts) =  # Move pts.low forward to the first index in   
  for i in pts.low .. pts.high:  # the point array that contains a valid point
    if Pts[i].bis:
      pts.low = i  # After 2*LifeTime, the pts.low should be at around (LifeTime in seconds)*PointsPerSec
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
  newVertexGroup([0, 0, 1] , [-1, -1, 1] , [1, -1, 1] , [1, 1, 1] , [-1, 1, 1] )
  newVertexGroup([0, 0, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1], [1, -1, -1])
  newVertexGroup([0, 1, 0] , [-1, 1, -1] , [-1, 1, 1] , [1, 1, 1] , [1, 1, -1] )
  newVertexGroup([0, -1, 0], [-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1])
  newVertexGroup([1, 0, 0] , [1, -1, -1] , [1, 1, -1] , [1, 1, 1] , [1, -1, 1] )
  newVertexGroup([-1, 0, 0], [-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1])

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

proc render(pts: var TPts) =
  for i in pts.low .. pts.high:
    if (Pts[i].bis == false):
      continue
    
    var pt: ptr TPt = addr pts[i]
    glMatrixMode(GL_MODELVIEW)
    glPopMatrix()
    glPushMatrix()
    glTranslatef(pt.p[x], pt.p[y], -(pt.p[z]))
    glScalef(pt.R * 2, pt.R * 2, pt.R * 2)
    glColor4f(0.7, 0.9, 0.2, 1)
    glDrawArrays(GL_QUADS, 0, NUM_VERTICES)

proc main = 
  init()
  var 
    window = newWnd((Width.positive, Height.positive), Title,
        hints=initHints(nMultiSamples=2, GL_API=initGL_API(version=glv21)))
    
    initT, endT = 0.0        # Reused variables for timing frames
    gpuInitT, gpuEndT = 0.0  # Reused variables for timing gpu use
    frameDur = 0.0           # Reused variable for storing the duration of the last frame
    spwnTmr = 0.0            # Timer for particle spawning
    cleanupTmr = 0.0         # Timer for cleaning up the particle array
    runTmr = 0.0             # Timer of total running time
    
    pts = TPts(low: 0, high: 0)
    frames: array[RunningTime * 1000, float64]    # Length of each frame
    gpuTimes: array[RunningTime * 1000, float64]  # Cpu time spent before swapping buffers for each frame
    curFrame = 0                                  # The current number of frames that have elapsed
    
  window.makeContextCurrent()
  swapInterval(0)
  loadExtensions()
  initScene()  
  discard loadCubeToGPU()
  
  while not shouldClose(window):
    initT = getTime()
    pts.move(frameDur, gravity)
    doWind(frameDur)
    
    if (spwnTmr >= SPAWN_INTERVAL):
      pts.spawn(SPAWN_INTERVAL)
      spwnTmr -= SPAWN_INTERVAL

    if (cleanupTmr >= MAX_LIFE/1000):
      pts.cleanupPtPool()
      cleanupTmr = 0
    
    pts.checkColls()
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    gpuInitT = getTime()
    pts.render()

    window.swapBufs()
    gpuEndT = getTime()
    pollEvents()

    endT = getTime()
    frameDur = endT-initT  # Calculate the length of the previous frame
    spwnTmr += frameDur
    cleanupTmr += frameDur
    runTmr += frameDur
    
    if (runTmr > MAX_LIFE/1000):    # Start collecting framerate data and profiling after a 
      frames[curFrame] = frameDur   # full MaxLife worth of particles have been spawned.
      gpuTimes[curFrame] = gpuEndT - gpuInitT
      curFrame += 1
    
    if (runTmr >= RUNNING_TIME):  # Animation complete 
      break
      
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
      stdout.write(formatFloat(1/frames[i], precision=6) & ",")
    
    stdout.write(".--\n") 
    
  cleanupBuffers()
  window.destroy()
  terminate()

when isMainModule:
  main()
