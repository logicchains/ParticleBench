#[feature(globs)];

extern mod glfw;
extern mod gl;

use gl::types::*;
use std::sys::*;
use std::cast;
use std::ptr;
use std::num::abs;
use std::num::pow;
use std::num::sqrt;

static PrintFrames : bool = true;
static Title: &'static str  = "ParticleBench";
static Width : uint  = 800;
static Height : uint = 600;

static MaxPts : u32       = RunningTime * PointsPerSec;
static MaxInitVel : u32   = 7;
static MaxScale : u32     = 4;
static MaxLife : u32      = 5000;
static PointsPerSec : u32 = 2000;
static PointsPerSecf : f64 = PointsPerSec as f64;

static StartX : f64     = MinX + (MinX+MaxX)/2.0;
static StartRangei : u32 = 15;
static StartRangef : f64 = StartRangei as f64;
static StartY : f64     = MaxY;
static StartDepth : f64 = MinDepth + (MinDepth+MaxDepth)/2.0;

static MinX : f64     = -80.0;
static MaxX : f64     = 80.0;
static MinY : f64    = -90.0;
static MaxY : f64    = 50.0;
static MinDepth : f64 = 50.0;
static MaxDepth : f64 = 250.0;

static WindChangef : f64 = 2000.0;
static WindChangei : u32 = WindChangef as u32;
static MaxWind : f64 = 3.0;
static SpawnInterval : f64 = 0.01;
static RunningTime : u32  = ((MaxLife / 1000) * 5) ;

static ambient : [GLfloat, ..4] = [0.8, 0.05, 0.1, 1.0];
static diffuse : [GLfloat, ..4] = [1.0, 1.0, 1.0, 1.0];
static lightPos : [GLfloat, ..4] = [( MinX + (MaxX-MinX)/2.0) as f32, MaxY as f32, MinDepth as f32, 1.0];

static mut frameInitT: f64= 0.0;
static mut frameEndT:  f64= 0.0;
static mut gpuInitT:   f64= 0.0;
static mut gpuEndT:    f64= 0.0;
static mut frameDur:   f64= 0.0;
static mut spwnTmr:    f64= 0.0;
static mut cleanupTmr: f64= 0.0;
static mut runTmr:     f64= 0.0;

static mut frames :[f64, .. RunningTime * 1000] = [0.0, .. RunningTime * 1000];
static mut gpuTimes :[f64, .. RunningTime * 1000] = [0.0, .. RunningTime * 1000];
static mut curFrame: u64 = 0;

static mut windX: f64 = 0.0;
static mut windY: f64 = 0.0;
static mut windZ: f64 = 0.0;
static mut grav:  f64 = 0.5;


static emptyPt : Pt = Pt{X:0.0,Y:0.0,Z:0.0,VX:0.0,VY:0.0,VZ:0.0,R:0.0,Life:0.0,is:false};
static mut Pts : [Pt, ..MaxPts] = [emptyPt, ..MaxPts];
static mut maxPt: int = 0;
static mut minPt: int = 0;
static mut seed: u32 = 1234569;

struct Pt {
	X: f64, Y: f64, Z: f64, VX: f64, VY: f64, VZ: f64, R: f64, Life: f64, 
	is: bool
}

static mut gVBO : GLuint  = 0;
static emptyVert : Vertex = Vertex{pos: [0.0,0.0,0.0], normal:[0.0,0.0,0.0]} ;
static mut Vertices :   [Vertex, ..24] = [emptyVert, ..24];
static mut curVertex :  u32 = 0;
static mut curNormalX : GLfloat = 0.0;
static mut curNormalY : GLfloat = 0.0;
static mut curNormalZ : GLfloat = 0.0;

struct Vertex {
	pos   :  [GLfloat, ..3],
	normal : [GLfloat, ..3]
}

fn newVertex(x: GLfloat, y: GLfloat, z: GLfloat  ) {
	unsafe{
		let newPos : [GLfloat, ..3] = [x, y, z];
		let newNormal : [GLfloat, ..3] = [curNormalX, curNormalY, curNormalZ];
		let thisVertex :  Vertex = Vertex{pos: newPos, normal: newNormal};
		Vertices[curVertex] = thisVertex;
		curVertex+=1;
	}
}

fn newNormal(nx: GLfloat, ny: GLfloat, nz : GLfloat) {
	unsafe{
		curNormalX = nx;
		curNormalY = ny;
		curNormalZ = nz;
	}
}

fn rand() -> u32 {
	unsafe{
		seed ^= seed << 13;
		seed ^= seed >> 17;
		seed ^= seed << 5;
		return seed;
	}
}

fn spwnPts(secs: f64) {
	unsafe {
		let num = (secs * PointsPerSecf) as u32;
		let mut i: u32 = 0;
		while i < num{
			Pts[maxPt] = Pt{X: 0.0 + (rand()%StartRangei) as f64 - StartRangef/2.0, Y: StartY,
				Z: StartDepth + (rand()%StartRangei) as f64 - StartRangef/2.0, VX: (rand() % MaxInitVel) as f64,
				VY: (rand() % MaxInitVel) as f64, VZ: (rand() % MaxInitVel) as f64,
				R: (rand()%(MaxScale*100)) as f64 / 200.0, Life: (rand()%MaxLife) as f64 / 1000.0, is: true};
			maxPt+=1;
			i+=1;
		}
	}
}

fn movPts(secs: f64) {
	unsafe {
		let mut i = minPt; 
		while i <= maxPt {		
			if Pts[i].is == false {
				i+=1;
				continue;
			}
			Pts[i].X += Pts[i].VX * secs;
			Pts[i].Y += Pts[i].VY * secs;
			Pts[i].Z += Pts[i].VZ * secs;
			Pts[i].VX += windX * 1.0 / Pts[i].R; // The effect of the wind on a particle is inversely proportional to its radius
			Pts[i].VY += windY * 1.0 / Pts[i].R;
			Pts[i].VY -= grav;
			Pts[i].VZ += windZ * 1.0 / Pts[i].R;
			Pts[i].Life -= secs;
			if Pts[i].Life <= 0.0 {
				Pts[i].is = false;
			}
			i+=1;
		}
	}
}

fn doWind() {
	unsafe {
		windX += ( ((rand()%WindChangei) as f64)/WindChangef - WindChangef/2000.0) * frameDur;
		windY += ( ((rand()%WindChangei) as f64)/WindChangef - WindChangef/2000.0) * frameDur;
		windZ += ( ((rand()%WindChangei) as f64)/WindChangef - WindChangef/2000.0) * frameDur;
		if abs(windX) > MaxWind {
			windX *= -0.5;
		}
		if abs(windY) > MaxWind {
			windY *= -0.5;
		}
		if abs(windZ) > MaxWind {
			windZ *= -0.5;
		}
	}
}

fn checkColls() {
	unsafe{
		let mut i = minPt;
		while i <= maxPt{
			if Pts[i].is == false {
				i+=1;			
				continue;			
			}
			if Pts[i].X < MinX {
				Pts[i].X = MinX + Pts[i].R;
				Pts[i].VX *= -1.1; // These particles are magic; they accelerate by 10% at every bounce off the bounding box
			}
			if Pts[i].X > MaxX {
				Pts[i].X = MaxX - Pts[i].R;
				Pts[i].VX *= -1.1;
			}
			if Pts[i].Y < MinY {
				Pts[i].Y = MinY + Pts[i].R;
				Pts[i].VY *= -1.1;
			}
			if Pts[i].Y > MaxY {
				Pts[i].Y = MaxY - Pts[i].R;
				Pts[i].VY *= -1.1;
			}
			if Pts[i].Z < MinDepth {
				Pts[i].Z = MinDepth + Pts[i].R;
				Pts[i].VZ *= -1.1;
			}
			if Pts[i].Z > MaxDepth {
				Pts[i].Z = MaxDepth - Pts[i].R;
				Pts[i].VZ *= -1.1;
			}
			i+=1;
		}
	}	
}

fn cleanupPtPool() { 
	unsafe{
		let mut i = minPt;
		while i <= maxPt{
			if Pts[i].is == true {
				minPt = i;
				break;
			}
			i+=1;
		}
	}
}

#[start]
fn start(argc: int, argv: **u8) -> int {
    // Run GLFW on the main thread
    std::rt::start_on_main_thread(argc, argv, main)
}

fn loadCubeToGPU() {
	newNormal(0.0, 0.0, 1.0);
	newVertex(-1.0, -1.0, 1.0);
	newVertex(1.0, -1.0, 1.0);
	newVertex(1.0, 1.0, 1.0);
	newVertex(-1.0, 1.0, 1.0);

	newNormal(0.0, 0.0, -1.0);
	newVertex(-1.0, -1.0, -1.0);
	newVertex(-1.0, 1.0, -1.0);
	newVertex(1.0, 1.0, -1.0);
	newVertex(1.0, -1.0, -1.0);

	newNormal(0.0, 1.0, 0.0);
	newVertex(-1.0, 1.0, -1.0);
	newVertex(-1.0, 1.0, 1.0);
	newVertex(1.0, 1.0, 1.0);
	newVertex(1.0, 1.0, -1.0);

	newNormal(0.0, -1.0, 0.0);
	newVertex(-1.0, -1.0, -1.0);
	newVertex(1.0, -1.0, -1.0);
	newVertex(1.0, -1.0, 1.0);
	newVertex(-1.0, -1.0, 1.0);

	newNormal(1.0, 0.0, 0.0);
	newVertex(1.0, -1.0, -1.0);
	newVertex(1.0, 1.0, -1.0);
	newVertex(1.0, 1.0, 1.0);
	newVertex(1.0, -1.0, 1.0);

	newNormal(-1.0, 0.0, 0.0);
	newVertex(-1.0, -1.0, -1.0);
	newVertex(-1.0, -1.0, 1.0);
	newVertex(-1.0, 1.0, 1.0);
	newVertex(-1.0, 1.0, -1.0);
	
	unsafe{
		let gVBOp : *mut u32 = &mut gVBO as *mut u32; 
		gl::GenBuffers(1, gVBOp);
		gl::BindBuffer(gl::ARRAY_BUFFER, gVBO);
		gl::BufferData(gl::ARRAY_BUFFER, (size_of_val(&emptyVert)*24) as GLsizeiptr,cast::transmute(&Vertices[0]), gl::STATIC_DRAW);
	}

	gl::EnableClientState(gl::VERTEX_ARRAY);
	gl::EnableClientState(gl::NORMAL_ARRAY);
	gl::VertexPointer(3, gl::FLOAT, 24, ptr::null());
	gl::NormalPointer(gl::FLOAT, 24, ptr::null());
}

fn initScene() {
	gl::Enable(gl::DEPTH_TEST);
	gl::Enable(gl::LIGHTING);

	gl::ClearColor(0.1, 0.1, 0.6, 1.0);
	gl::ClearDepth(1.0);
	gl::DepthFunc(gl::LEQUAL);

	gl::Lightfv(gl::LIGHT0, gl::AMBIENT, &ambient[0]);
	gl::Lightfv(gl::LIGHT0, gl::DIFFUSE, &diffuse[0]);
	gl::Lightfv(gl::LIGHT0, gl::POSITION, &lightPos[0]);
	gl::Enable(gl::LIGHT0);

	gl::Viewport(0, 0, Width as i32, Height as i32);
	gl::MatrixMode(gl::PROJECTION);
	gl::LoadIdentity();
	gl::Frustum(-1.0, 1.0, -1.0, 1.0, 1.0, 1000.0);
	gl::Rotatef(20.0, 1.0, 0.0, 0.0);
	gl::MatrixMode(gl::MODELVIEW);
	gl::LoadIdentity();
	gl::PushMatrix();

	return
}

fn renderPts() {
	unsafe{
		gl::MatrixMode(gl::MODELVIEW);
		let mut i = minPt;
		while i <= maxPt {
			if Pts[i].is == false {
				i+=1;
				continue;
			}
			let pt = &Pts[i];
			gl::PopMatrix();
			gl::PushMatrix();
			gl::Translatef(pt.X as GLfloat, pt.Y as GLfloat, -pt.Z as GLfloat);
			gl::Scalef((pt.R*2.0) as GLfloat, (pt.R*2.0) as GLfloat, (pt.R*2.0) as GLfloat);
			gl::DrawArrays(gl::QUADS, 0, 24);
			i+=1;
		}
	}
}

fn main() {
    do glfw::set_error_callback |_, description| {
        format!("GLFW Error: {}", description);
    }

    do glfw::start {
	glfw::window_hint::context_version(2, 1);
	//glfw::window_hint::samples(2);
        let window = glfw::Window::create(Width, Height, Title, glfw::Windowed)
            .expect("Failed to create GLFW window.");
        window.make_context_current();

	glfw::set_swap_interval(0);
	gl::load_with(glfw::get_proc_address);

	initScene();
	loadCubeToGPU();
        while !window.should_close() {
		unsafe{ 
			frameInitT = glfw::get_time();  
			movPts(frameDur);

			doWind();		
				
			if spwnTmr >= SpawnInterval {
				spwnPts(SpawnInterval);
				spwnTmr -= SpawnInterval;
			}		
			if cleanupTmr >= MaxLife as f64/1000.0 {
				cleanupPtPool();
				cleanupTmr = 0.0;
			}

			checkColls();
			gl::Clear(gl::COLOR_BUFFER_BIT | gl::DEPTH_BUFFER_BIT);
			gpuInitT = glfw::get_time();
			renderPts();	
			window.swap_buffers();
			gpuEndT = glfw::get_time();
			glfw::poll_events();

			frameEndT = glfw::get_time();
			frameDur = frameEndT-frameInitT;
			spwnTmr += frameDur;
			cleanupTmr += frameDur;
			runTmr += frameDur;
			if runTmr > MaxLife as f64/1000.0{
				frames[curFrame] = frameDur;
				gpuTimes[curFrame] = gpuEndT-gpuInitT;
				curFrame += 1;
			}
			if runTmr >= RunningTime as f64 { // Animation complete; calculate framerate mean and standard deviation
				let mut sum : f64 = 0.0;
				let mut i : u64 = 0;
				while i < curFrame {
					sum += frames[i];
					i+=1;
				}
				let frameTimeMean  = sum / (curFrame as f64);
				println!("Average framerate was: {} frames per second.", 1.0/frameTimeMean);

				sum = 0.0;
				while i < curFrame {
					sum += gpuTimes[i];
					i+=1;
				}
				let gpuTimeMean  = sum / (curFrame as f64);
				println!("Average cpu time was- {} seconds per frame.", frameTimeMean - gpuTimeMean)

				let mut sumDiffs = 0.0;
				i = 0;
				while i < curFrame {
					sumDiffs += pow( (1.0/(frames[i])-1.0/(frameTimeMean) ) as f64, 2.0);
					i+=1;
				}
				let variance = sumDiffs / (curFrame as f64);
				let sd = sqrt(variance);
				println!("The standard deviation was: {} frames per second.", sd);
				if (PrintFrames == true){
					print!("--:");
					i = 0;
					while i < curFrame {
						print( (1.0/frames[i]).to_str() );
						print!(",");
						i+=1;
					}
					print!(".--");
				}						
				break;
			}
	        }
	}
    }
}

