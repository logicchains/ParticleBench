import opengl, glfw/glfw, math, unsigned, strutils, sequtils

from glfw/wrapper import getTime

type
  TCoord = enum
    x, y, z

  TPt = ref object
    p, v : array[TCoord, float64]
    r, life: float64
    bis: bool

  TVertex = object
    pos: array[TCoord, GLfloat]
    normal: array[TCoord, GLfloat]

const
  PrintFrames = true
  Title = "ParticleBench"
  Width = 800
  Height = 600

  MaxLife = 5000
  PointsPerSec = 2000
  RunningTime = (MaxLife div 1000) * 4
  MaxPts = RunningTime * PointsPerSec
  MaxInitVel = 7
  MaxScale = 4

  Min: array[TCoord, float] = [-80.0, -90.0, 50.0]
  Max: array[TCoord, float] = [80.0, 50.0, 250.0]
  
  StartRange = 15
  StartY = Max[y]
  StartDepth = (Min[z] + (Min[z]+Max[z])/2)

  Gravity = 50'f64 
  WindChange = 2000
  MaxWind = 3
  SpawnInterval = 0.01
  NumVertices = 24

type
  PPts = ref object
    low, high: int
    pool: array[MaxPts, TPt]

proc initPts(): PPts =
  result = PPts(low: 0, high: 0)
  for i in 0 .. <MaxPts:
    new(result.pool[i])

var
  ambient = [Glfloat(0.8), 0.05, 0.1, 1.0]
  diffuse = [Glfloat(1.0), 1.0, 1.0, 1.0]
  lightPos = [GlFloat(Min[x] + (Max[x]-Min[x])/2), 
              Max[y], Min[z], 0]
              
  vertices: array[NumVertices, TVertex]  
  wind: array[TCoord, float64] = [0.0, 0.0, 0.0]
  gVBO: GLuint = 0
  pts = initPts()


proc `[]`(pts: var PPts, key: int): var TPt = pts.pool[key]
proc `[]=`(pts: var PPts, key: int, val: TPt) = pts.pool[key] = val

converter toGlVec(a: Array[3, int]) : array[TCoord, GLfloat] = 
  return [a[x.ord].GlFloat, a[y.ord].GlFloat, a[z.ord].GlFloat]

proc newVertexGroup(normal: Array[3, int], pos: varargs[Array[3, int]]) =
  var curVertex {.global.} = 0
  for p in pos:
    vertices[curVertex] = TVertex(pos: p, normal: normal)
    curVertex.inc

proc xorRand: uint32 =
  var seed {.global.} = 1234569'u32
  seed = seed xor (seed shl 13)
  seed = seed xor (seed shr 17)
  seed = seed xor (seed shl 5)
  return seed

proc move(pts: var PPts, secs) =
  for i in pts.low .. pts.high:
    if not pts[i].bis:
      continue
    for c in TCoord:
      pts[i].p[c] += pts[i].v[c] * secs
      pts[i].v[c] += wind[c] * 1 / pts[i].r
    pts[i].v[y] -= Gravity * secs
    pts[i].life -= secs
    
    if pts[i].life <= 0:
      pts[i].bis = false
      
proc spawn(pts: var PPts, secs: float64) =
  let num = secs * PointsPerSec
  for i in 0 .. <num.int:
    pts[pts.high] = TPt(
      p: [0 + float64(xorRand() mod StartRange) - StartRange/2,
        startY,
        startDepth + float64(xorRand() mod StartRange) - StartRange/2],
      v: [float64(xorRand() mod MaxInitVel),
        float64(xorRand() mod MaxInitVel),
        float64(xorRand() mod MaxInitVel)],
      r: float64(xorRand() mod (MaxScale*100)) / 200,
      life: float64(xorRand() mod MaxLife) / 1000,
      bis: true
    )
    pts.high.inc

proc doWind(secs: float64) =
  for c in TCoord:
    wind[c] += (float64(xorRand() mod WindChange)/WindChange - WindChange/2000) * secs
    if abs(wind[c]) > MaxWind:
      wind[c] *= -0.5

proc checkColls(pts: var PPts) =
  for i in pts.low .. pts.high:
    if not pts[i].bis:
      continue
    for c in TCoord:
      if pts[i].p[c] < Min[c]:
        pts[i].p[c] = Min[c] + pts[i].r
        pts[i].v[c] *= -1.1
      if pts[i].p[c] > Max[c]:
        pts[i].p[c] = Max[c] - pts[i].r
        pts[i].v[c] *= -1.1

proc cleanupPtPool(pts: var PPts) =
  for i in pts.low .. pts.high:
    if Pts[i].bis:
      pts.low = i
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

  glViewport(0, 0, Width, Height)
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
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(NumVertices * sizeof(TVertex)), addr vertices[0], GL_STATIC_DRAW)

  glEnableClientState(GL_VERTEX_ARRAY)
  glEnableClientState(GL_NORMAL_ARRAY)

  glVertexPointer(3, cGL_FLOAT, sizeof(TVertex).glsizei, nil)        
  glNormalPointer(cGL_FLOAT, sizeof(TVertex).glsizei, cast[pglvoid](offsetof(TVertex, normal)))        

  return true

proc cleanupBuffers =
  glDeleteBuffers( 1, addr gVBO)
  glDisableClientState( GL_NORMAL_ARRAY )
  glDisableClientState( GL_VERTEX_ARRAY )

proc render(pts: var PPts) =
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
    glDrawArrays(GL_QUADS, 0, NumVertices)

proc main =
  GC_disable()
  init()
  var 
    window = newWnd((Width.positive, Height.positive), Title,
        hints=initHints(nMultiSamples=2, GL_API=initGL_API(version=glv21)))
    
    initT = 0.0
    gpuInitT, gpuEndT = 0.0
    frameDur = 0.0
    spwnTmr = 0.0
    cleanupTmr = 0.0
    runTmr = 0.0
    
    frames = newSeq[float]()
    gpuTimes = newSeq[float]()
    
  window.makeContextCurrent()
  swapInterval(0)
  loadExtensions()
  initScene()  
  discard loadCubeToGPU()
  
  while not shouldClose(window):
    initT = getTime()
    pts.move(frameDur)
    doWind(frameDur)
    
    if (spwnTmr >= SpawnInterval):
      pts.spawn(SpawnInterval)
      spwnTmr -= SpawnInterval

    if (cleanupTmr >= MaxLife/1000):
      pts.cleanupPtPool()
      cleanupTmr = 0
    
    pts.checkColls()
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    gpuInitT = getTime()
    pts.render()

    window.swapBufs()
    gpuEndT = getTime()
    pollEvents()

    frameDur = getTime() - initT
    spwnTmr += frameDur
    cleanupTmr += frameDur
    runTmr += frameDur
    
    if (runTmr > MaxLife/1000):
      frames.add(frameDur)
      gpuTimes.add(gpuEndT - gpuInitT)
    
    if (runTmr >= RunningTime):
      break
    
    GC_step(1000)
    
  let frameTimeMean = mean(frames)
  echo("Average framerate was: $1 frames per second." % (1/frameTimeMean).formatFloat)
  
  let gpuTimeMean = mean(gpuTimes)
  echo("Average cpu time was- $1 seconds per frame." %
       formatFloat(frameTimeMean - gpuTimeMean))
  
  let sumDiffs = foldl(frames, a + pow((1/b)-(1/frameTimeMean), 2))
  let sd = sqrt(sumDiffs / frames.len.float64)
  echo("The standard deviation was: $1 frames per second." % sd.formatFloat)
  
  when PrintFrames:
    stdout.write("--:")
    for f in frames:
      stdout.write(formatFloat(1/f, precision=6) & ",")
    
    stdout.write(".--\n") 
    
  cleanupBuffers()
  window.destroy()
  terminate()

when isMainModule:
  main()
