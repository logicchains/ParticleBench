package main

import (
	"fmt"
	//"github.com/go-gl/gl"
	gl "github.com/chsc/gogl/gl21"
	glfw "github.com/go-gl/glfw3"
	"math"
	"os"
	"runtime/pprof"
	"time"
	"unsafe"
)

const (
	Title  = "ParticleBench"
	Width  = 800
	Height = 600

	MaxPts       = RunningTime * PointsPerSec // The size of the particle pool
	MaxInitVel   = 7                          // The maximum initial speed of a newly created particle
	MaxScale     = 4                          // The maximum scale of a particle
	MaxLife      = 5000                       // Maximum particle lifetime in milliseconds
	PointsPerSec = 2000                       // Particles created per second

	StartX     = MinX + (MinX+MaxX)/2 // Starting X position of a particle
	StartRange = 15                   // Twice the maximum distance a particle may be spawned from the start point
	StartY     = MaxY
	StartDepth = MinDepth + (MinDepth+MaxDepth)/2

	MinX     = -80 // Minimum X position of a particle; bounding box minimum
	MaxX     = 80
	MinY     = -90 // The Y axis is height, the Z axis is depth
	MaxY     = 50
	MinDepth = 50
	MaxDepth = 250

	WindChange    = 2000                 // The maximum change in windspeed per second, in milliseconds
	MaxWind       = 3                    // Maximum windspeed in seconds before wind is reversed at half speed
	SpawnInterval = 0.01                 // How often particles are spawned, in millisecons
	RunningTime   = (MaxLife / 1000) * 5 // The total running time of the animation
)

var (
	ambient  []gl.Float = []gl.Float{0.8, 0.05, 0.1, 1}                        // Ambient light
	diffuse  []gl.Float = []gl.Float{1, 1, 1, 1}                              // Diffuse light
	lightPos []gl.Float = []gl.Float{MinX + (MaxX-MinX)/2, MaxY, MinDepth, 0} // Position of the lightsource

	Pts    [MaxPts]Pt           // The pool of particles
	numPts int                  // The maximum index in the pool that currently contains a particle
	minPt  int                  // The minimum index in the pool that currently contains a particle, or zero.
	seed   uint32     = 1234569 // Initial PRNG seed

	frameInitT time.Time // Reused variable for timing frames
	frameEndT  time.Time // Reused variable for timing frames
	frameDur   float64   // Reused variable for storing the duration of the last frame
	spwnTmr    float64   // Timer for particle spawning
	cleanupTmr float64   // Timer for cleaning up the particle array
	runTmr     float64   // Timer of total running timer

	frames   [RunningTime * 1000]float64 // Array for storing the length of each frame
	curFrame uint64                      // The current number of frames that have elapsed

	windX float64 = 0 // Windspeed
	windY float64 = 0
	windZ float64 = 0
	grav  float64 = 0.5

	gVBO gl.Uint 
	Vertices [24]Vertex
	curVertex uint32
	curNormalX gl.Float
	curNormalY gl.Float
	curNormalZ gl.Float	
)

func errorCallback(err glfw.ErrorCode, desc string) {
	fmt.Printf("%v: %v\n", err, desc)
}

type Pt struct {
	X, Y, Z, VX, VY, VZ, R, Life float64 // The position, velocity, radius, and remaining lifetime of a particle
	is                           bool    // Whether this index in the pool (array) is currently occupied by a living particle or not
}

type Vertex struct {
	pos [3]gl.Float
	normal [3]gl.Float
}


func newVertex(x,y,z gl.Float){
	newPos := [3]gl.Float{x,y,z}
	newNormal := [3]gl.Float{curNormalX,curNormalY,curNormalZ}
	thisVertex := Vertex{pos: newPos, normal: newNormal}
	Vertices[curVertex] = thisVertex
	fmt.Println(Vertices[curVertex])
	curVertex++
}

func newNormal(nx,ny,nz gl.Float){
	curNormalX = nx
	curNormalY = ny
	curNormalZ = nz
}

func rand() uint32 {
	seed ^= seed << 13
	seed ^= seed >> 17
	seed ^= seed << 5
	return seed
}

func spwnPts(secs float64) {
	num := uint32(secs * PointsPerSec)
	var i uint32 = 0
	for ; i < num; i++ {
		Pts[numPts] = Pt{X: 0 + float64(rand()%StartRange) - StartRange/2, Y: StartY,
			Z: StartDepth + float64(rand()%StartRange) - StartRange/2, VX: float64(rand() % MaxInitVel),
			VY: float64(rand() % MaxInitVel), VZ: float64(rand() % MaxInitVel),
			R: float64(rand()%(MaxScale*100)) / 200, Life: float64(rand()%MaxLife) / 1000, is: true}
		numPts++
	}
}

func movPts(secs float64) {
	for i := minPt; i <= numPts; i++ {
		if Pts[i].is == false {
			continue
		}
		Pts[i].X += Pts[i].VX * secs
		Pts[i].Y += Pts[i].VY * secs
		Pts[i].Z += Pts[i].VZ * secs
		Pts[i].VX += windX * 1 / Pts[i].R // The effect of the wind on a particle is inversely proportional to its radius
		Pts[i].VY += windY * 1 / Pts[i].R
		Pts[i].VY -= grav
		Pts[i].VZ += windZ * 1 / Pts[i].R
		Pts[i].Life -= secs
		if Pts[i].Life <= 0 {
			Pts[i].is = false
		}
	}
}

func checkColls() {
	for i := minPt; i <= numPts; i++ {
		if Pts[i].is == false {
			continue
		}
		if Pts[i].X < MinX {
			Pts[i].X = MinX + Pts[i].R
			Pts[i].VX *= -1.1 // These particles are magic; they accelerate by 10% at every bounce off the bounding box
		}
		if Pts[i].X > MaxX {
			Pts[i].X = MaxX - Pts[i].R
			Pts[i].VX *= -1.1
		}
		if Pts[i].Y < MinY {
			Pts[i].Y = MinY + Pts[i].R
			Pts[i].VY *= -1.1
		}
		if Pts[i].Y > MaxY {
			Pts[i].Y = MaxY - Pts[i].R
			Pts[i].VY *= -1.1
		}
		if Pts[i].Z < MinDepth {
			Pts[i].Z = MinDepth + Pts[i].R
			Pts[i].VZ *= -1.1
		}
		if Pts[i].Z > MaxDepth {
			Pts[i].Z = MaxDepth - Pts[i].R
			Pts[i].VZ *= -1.1
		}
	}
}

func cleanupPtPool() { // move minPt forward to the first index in the point array that contains a valid point
	for i := 0; i <= numPts; i++ {
		if Pts[i].is == true {
			minPt += i // After 2*LifeTime, the minPt should be at around (LifeTime in seconds)*PointsPerSec
			break
		}
	}
}

func doWind() {
	windX += (float64(rand()%WindChange)/WindChange - WindChange/2000) * frameDur
	windY += (float64(rand()%WindChange)/WindChange - WindChange/2000) * frameDur
	windZ += (float64(rand()%WindChange)/WindChange - WindChange/2000) * frameDur
	if math.Abs(windX) > MaxWind {
		windX *= -0.5
	}
	if math.Abs(windY) > MaxWind {
		windY *= -0.5
	}
	if math.Abs(windZ) > MaxWind {
		windZ *= -0.5
	}
}

func main() {
	f, err := os.Create("Go.pprof") // Create file for profiling
	if err != nil {
		panic(err)
	}

	glfw.SetErrorCallback(errorCallback)
	if !glfw.Init() {
		panic("Can't init glfw!")
	}
	defer glfw.Terminate()
	glfw.WindowHint(glfw.Samples, 2);
	glfw.WindowHint(glfw.ContextVersionMajor, 2);
	glfw.WindowHint(glfw.ContextVersionMinor, 1);
	window, err := glfw.CreateWindow(Width, Height, Title, nil, nil)
	if err != nil {
		panic(err)
	}
	window.MakeContextCurrent()

	glfw.SwapInterval(0) // No limit on FPS
	gl.Init()
	initScene()
	loadCubeToGPU()
	for !window.ShouldClose() {
		frameInitT = time.Now()
		movPts(frameDur)
		doWind()
		if spwnTmr >= SpawnInterval {
			spwnPts(SpawnInterval)
			spwnTmr -= SpawnInterval
		}
		if cleanupTmr >= float64(MaxLife)/1000 {
			cleanupPtPool()
			cleanupTmr = 0
		}
		checkColls()
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		renderPts()
		window.SwapBuffers()
		glfw.PollEvents()
		frameEndT = time.Now()
		frameDur = frameEndT.Sub(frameInitT).Seconds() // Calculate the length of the previous frame
		spwnTmr += frameDur
		cleanupTmr += frameDur
		runTmr += frameDur
		if runTmr > MaxLife/1000 { // Start collecting framerate data and profiling after a full MaxLife worth of particles have been spawned
			frames[curFrame] = frameDur
			curFrame += 1
			pprof.StartCPUProfile(f)
		}
		if runTmr >= RunningTime { // Animation complete; calculate framerate mean and standard deviation
			pprof.StopCPUProfile()
			var sum float64
			var i uint64
			for i = 0; i < curFrame; i++ {
				sum += frames[i]
			}
			mean := sum / float64(curFrame)
			fmt.Println("Average framerate was:", 1/mean, "frames per second.")
			sumDiffs := 0.0
			for i = 0; i < curFrame; i++ {
				sumDiffs += math.Pow(1/frames[i]-1/mean, 2)
			}
			variance := sumDiffs / float64(curFrame)
			sd := math.Sqrt(variance)
			fmt.Println("The standard deviation was:", sd, "frames per second.")
			break
		}
	
	}
	gl.DisableClientState( gl.NORMAL_ARRAY );
	gl.DisableClientState( gl.VERTEX_ARRAY );
}

func initScene() {
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.LIGHTING)

	gl.ClearColor(0.1, 0.1, 0.6, 1.0)
	gl.ClearDepth(1)
	gl.DepthFunc(gl.LEQUAL)

	gl.Lightfv(gl.LIGHT0, gl.AMBIENT, &ambient[0])
	gl.Lightfv(gl.LIGHT0, gl.DIFFUSE, &diffuse[0])
	gl.Lightfv(gl.LIGHT0, gl.POSITION, &lightPos[0])
	gl.Enable(gl.LIGHT0)

	gl.Viewport(0, 0, Width, Height)
	gl.MatrixMode(gl.PROJECTION)
	gl.LoadIdentity()
	gl.Frustum(-1, 1, -1, 1, 1.0, 1000.0)
	gl.Rotatef(20, 1, 0, 0)
	gl.MatrixMode(gl.MODELVIEW)
	gl.LoadIdentity()
	gl.PushMatrix()

	return
}

func loadCubeToGPU(){
	newNormal(0, 0, 1)
	newVertex(-1, -1, 1)
	newVertex(1, -1, 1)
	newVertex(1, 1, 1)
	newVertex(-1, 1, 1)

	newNormal(0, 0, -1)
	newVertex(-1, -1, -1)
	newVertex(-1, 1, -1)
	newVertex(1, 1, -1)
	newVertex(1, -1, -1)

	newNormal(0, 1, 0)
	newVertex(-1, 1, -1)
	newVertex(-1, 1, 1)
	newVertex(1, 1, 1)
	newVertex(1, 1, -1)

	newNormal(0, -1, 0)
	newVertex(-1, -1, -1)
	newVertex(1, -1, -1)
	newVertex(1, -1, 1)
	newVertex(-1, -1, 1)

	newNormal(1, 0, 0)
	newVertex(1, -1, -1)
	newVertex(1, 1, -1)
	newVertex(1, 1, 1)
	newVertex(1, -1, 1)

	newNormal(-1, 0, 0)
	newVertex(-1, -1, -1)
	newVertex(-1, -1, 1)
	newVertex(-1, 1, 1)
	newVertex(-1, 1, -1)

	gl.GenBuffers( 1, &gVBO )
	gl.BindBuffer( gl.ARRAY_BUFFER, gVBO )
	gl.BufferData( gl.ARRAY_BUFFER, gl.Sizeiptr(unsafe.Sizeof(Vertex{})*24), gl.Pointer(&Vertices[0]), gl.STATIC_DRAW )
	
	gl.EnableClientState( gl.VERTEX_ARRAY );
	gl.EnableClientState( gl.NORMAL_ARRAY );	
	gl.VertexPointer( 3, gl.FLOAT, 24, nil );	
	gl.NormalPointer( gl.FLOAT, 12, nil);	
}

func renderPts(){
	gl.MatrixMode(gl.MODELVIEW);	
	for i := minPt; i <= numPts; i++ {
		if (Pts[i].is == false) {
			continue
		}
		pt := &Pts[i];
		gl.PopMatrix();
		gl.PushMatrix();
		gl.Translatef(gl.Float((*pt).X), gl.Float((*pt).Y), -gl.Float((*pt).Z));
		gl.Scalef(gl.Float((*pt).R * 2), gl.Float((*pt).R*2), gl.Float((*pt).R*2));
		gl.DrawArrays( gl.QUADS, 0, 24 );	
	}
}
