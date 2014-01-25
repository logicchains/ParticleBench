using System;
using OpenTK;
using OpenTK.Graphics;
using OpenTK.Graphics.OpenGL;
using OpenTK.Input;

namespace ParticleBench
{
	class Bench : GameWindow{
		public Bench()
            	: base(Globals.WIDTH, Globals.HEIGHT, GraphicsMode.Default, Globals.TITLE){
		VSync = VSyncMode.Off;
	}
	protected override void OnLoad(EventArgs e){
		base.OnLoad(e);
		Globals.initScene();
		Globals.loadCubeToGPU();
	}
        protected override void OnResize(EventArgs e){
		base.OnResize(e);
        }
	protected override void OnUpdateFrame(FrameEventArgs e){
		base.OnUpdateFrame(e);
		Globals.mainLoop();
		SwapBuffers();
		if (Keyboard[Key.Escape])
			Exit();
	}
	protected override void OnRenderFrame(FrameEventArgs e){
		base.OnRenderFrame(e);
	}

	[STAThread]
	static void Main(){
		using (Bench bench = new Bench()){
			bench.Run(200.0);
		}
	}
    }
}


public class Pt {
	public double X; public double Y; public double Z; public double VX; public double VY; public double VZ; public double R; public double Life; 
	public bool alive;
}

public class Vertex {
	public float[] pos = new float[3];
	public float[] normal = new float[3];
}


public static class Globals{
	public const bool PRINT_FRAMES = true;
	public const string TITLE = "ParticleBench";
	public const int WIDTH = 800;
	public const int HEIGHT = 600;

	public const int MIN_X = -80;
	public const int MAX_X = 80;
	public const int MIN_Y = -90;
	public const int MAX_Y = 50;
	public const int MIN_DEPTH = 50;
	public const int MAX_DEPTH = 250;

	public const int START_RANGE = 15;
	public const int START_X = (MIN_X + (MIN_X+MAX_X)/2);
	public const int START_Y = MAX_Y;
	public const int START_DEPTH = (MIN_DEPTH + (MIN_DEPTH+MAX_DEPTH)/2);

	public const int POINTS_PER_SEC = 2000;
	public const int MAX_INIT_VEL = 7;
	public const int MAX_LIFE = 5000;
	public const int MAX_SCALE = 4;

	public const int WIND_CHANGE = 2000;
	public const int MAX_WIND = 3;
	public const double SPAWN_INTERVAL = 0.01 ;
	public const int RUNNING_TIME = ((MAX_LIFE / 1000) * 4);
	public const int MAX_PTS = (RUNNING_TIME * POINTS_PER_SEC);

	public static float[] ambient = {0.8f, 0.05f, 0.1f, 1f};
	public static float[] diffuse = {1.0f, 1.0f, 1.0f, 1f};
	public static float[] lightPos = {MIN_X + (MAX_X-MIN_X)/2, MAX_Y, MIN_DEPTH, 0};

	public static double[] frames = new double[RUNNING_TIME * 1000];
	public static double[] gpuTimes = new double[RUNNING_TIME * 1000];
	public static int curFrame = 0;
	public static Pt[] Pts = new Pt[MAX_PTS];
	public static Vertex[] Vertices = new Vertex[24];

	public static double windX = 0; 
	public static double windY = 0;
	public static double windZ = 0;
	public static double grav = 50;

	public static double initT = 0;
	public static double endT = 0;
	public static double gpuInitT = 0;
	public static double gpuEndT = 0;
	public static double frameDur = 0;
	public static double spwnTmr = 0;
	public static double cleanupTmr = 0;
	public static double runTmr = 0;

	public static int numPts = 0;      
	public static int minPt = 0;       
	public static uint seed = 1234569;

	public static int curVertex = 0;
	public static int curNormalX = 0;
	public static int curNormalY = 0;
	public static int curNormalZ = 0;

	public static void newVertex(int x,int y,int z){
		Vertex thisVertex = new Vertex();
		thisVertex.pos[0] = x;
		thisVertex.pos[1] = y;
		thisVertex.pos[2] = z;

		thisVertex.normal[0] = curNormalX;
		thisVertex.normal[1] = curNormalY;
		thisVertex.normal[2] = curNormalZ;

		Vertices[curVertex] = thisVertex;
		curVertex++;
	}

	public static void newNormal(int nx,int ny,int nz){
		curNormalX = nx;
		curNormalY = ny;
		curNormalZ = nz;
	}
	
	public static void loadCubeToGPU(){
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

		int gVBO = 0;
		GL.GenBuffers(1, out gVBO);
		GL.BindBuffer(BufferTarget.ArrayBuffer, gVBO);
		float[] PosnNormals = new float[Vertices.Length * 6];
		for (int i =0; i< Vertices.Length; i++){
			PosnNormals[i*6] = Vertices[i].pos[0];
			PosnNormals[i*6+1] = Vertices[i].pos[1];
			PosnNormals[i*6+2] = Vertices[i].pos[2];
			PosnNormals[i*6+3] = Vertices[i].normal[0];
			PosnNormals[i*6+4] = Vertices[i].normal[1];
			PosnNormals[i*6+5] = Vertices[i].normal[2];
		}
		GL.BufferData(BufferTarget.ArrayBuffer, (IntPtr)(PosnNormals.Length * sizeof(float)), IntPtr.Zero, BufferUsageHint.StaticDraw);
		IntPtr VideoMemoryIntPtr = GL.MapBuffer(BufferTarget.ArrayBuffer, BufferAccess.WriteOnly);
		unsafe{
			fixed ( float* SystemMemory = &PosnNormals[0] ){
				float* VideoMemory = (float*) VideoMemoryIntPtr.ToPointer();
				for ( int i = 0; i < PosnNormals.Length; i++ ) 
					VideoMemory[ i ] = SystemMemory[ i ];
			}	
		}
		GL.UnmapBuffer( BufferTarget.ArrayBuffer );

		GL.EnableClientState(EnableCap.VertexArray);
		GL.EnableClientState(EnableCap.NormalArray);
		GL.VertexPointer(3, VertexPointerType.Float, 24, new IntPtr(0));
		GL.NormalPointer(NormalPointerType.Float, 24, new IntPtr(12));
		GL.MatrixMode(MatrixMode.Modelview);
	}

	public static uint rand(){
    		seed ^= seed << 13;
	    	seed ^= seed >> 17;
    		seed ^= seed << 5;
    		return seed;
	}

	public static void movPts(double secs) {
		for (int i = minPt; i < numPts; i++) {
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
	
	public static void spwnPts(double secs) {
		int num = (int)(secs * POINTS_PER_SEC);
		int i = 0;
		for (; i < num; i++) {
			Pt pt = new Pt();
			pt.X = 0 + (float)(rand()%START_RANGE) - START_RANGE/2;
			pt.Y = START_Y;
			pt.Z = START_DEPTH + (float)(rand()%START_RANGE) - START_RANGE/2;
			pt.VX = (float)(rand() % MAX_INIT_VEL);
			pt.VY = (float)(rand() % MAX_INIT_VEL);
			pt.VZ = (float)(rand() % MAX_INIT_VEL);
			pt.R = (float)(rand() % (MAX_SCALE*100)) / 200;
			pt.Life = (float)(rand() % MAX_LIFE) / 1000;
			pt.alive = true;
			Pts[numPts] = pt;
			numPts++;
		}
	}

	public static void doWind() {
		windX += ( (double)(rand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
		windY += ( (double)(rand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
		windZ += ( (double)(rand() % WIND_CHANGE)/WIND_CHANGE - WIND_CHANGE/2000) * frameDur;
		if (Math.Abs(windX) > MAX_WIND) {
			windX *= -0.5;
		}
		if (Math.Abs(windY) > MAX_WIND) {
			windY *= -0.5;
		}
		if (Math.Abs(windZ) > MAX_WIND) {
			windZ *= -0.5;
		}
	}

	public static void checkColls() {
		for (int i = minPt; i < numPts; i++) {
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

	public static void cleanupPtPool() {
		for (int i = minPt; i <= numPts; i++) {
			if (Pts[i].alive == true) {
				minPt = i;
				break;
			}
		}
	}

	public static void initScene() {
		GL.Enable(EnableCap.DepthTest);

		GL.Light(LightName.Light0, LightParameter.Ambient, ambient);		
		GL.Light(LightName.Light0, LightParameter.Diffuse, diffuse);
		GL.Light(LightName.Light0, LightParameter.Position, lightPos);
		GL.Enable(EnableCap.Light0);
		GL.Enable(EnableCap.Lighting);
	
		GL.ClearColor(0.1f, 0.1f, 0.6f, 1.0f);
		GL.ClearDepth(1);
		GL.DepthFunc(DepthFunction.Lequal);

		GL.Viewport(0, 0, WIDTH, HEIGHT);
		GL.MatrixMode(MatrixMode.Projection);
		GL.LoadIdentity();
		GL.Frustum(-1.0, 1.0, -1.0, 1.0, 1.0, 1000.0);
		GL.Rotate(20.0, 1.0, 0.0, 0.0);
		GL.MatrixMode(MatrixMode.Modelview);
		GL.LoadIdentity();
		GL.PushMatrix();
		
		return;
	}
	public static void renderPts(){
		GL.MatrixMode(MatrixMode.Modelview);
	
		for (int i = minPt; i < numPts; i++) {
			if (Pts[i].alive == false) {
				continue;
			}
			Pt pt = Pts[i];
			GL.PopMatrix();
			GL.PushMatrix();
			GL.Translate(pt.X, pt.Y, -pt.Z);
			GL.Scale(pt.R * 2, pt.R*2, pt.R*2);
			GL.DrawArrays( BeginMode.Quads, 0, 24 );
		}
	}

	public static void mainLoop(){
		long milliseconds = DateTime.Now.Ticks / TimeSpan.TicksPerMillisecond;
		initT = milliseconds;
		movPts(frameDur);
		doWind();
		if (spwnTmr >= SPAWN_INTERVAL) {
			spwnPts(SPAWN_INTERVAL);
			spwnTmr -= SPAWN_INTERVAL;
		}
		if (cleanupTmr >= (double)(MAX_LIFE)/1000) {
			cleanupPtPool();
			cleanupTmr = 0;
		}
		checkColls();

		GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit);
		milliseconds = DateTime.Now.Ticks / TimeSpan.TicksPerMillisecond;
		gpuInitT = milliseconds;		
		renderPts();
	
		milliseconds = DateTime.Now.Ticks / TimeSpan.TicksPerMillisecond;
		gpuEndT = milliseconds;
		endT = milliseconds;
		frameDur = (endT-initT)/1000;
		spwnTmr += frameDur;
		cleanupTmr += frameDur;
		runTmr += frameDur;
		if (runTmr > MAX_LIFE/1000) { 
			frames[curFrame] = frameDur;
			gpuTimes[curFrame] = (gpuEndT-gpuInitT)/1000;
			curFrame += 1;			
		}
		
		if (runTmr >= RUNNING_TIME) {
			double sum = 0;
			int i = 0;
			for (i = 0; i < curFrame; i++) {
				sum += frames[i];
			}
			double frameTimeMean = sum / (double)curFrame;
			System.Console.Write("Average framerate was: ");
			System.Console.Write(1/frameTimeMean);
			System.Console.Write(" frames per second.\n");		

			sum = 0;
			for (i = 0; i < curFrame; i++) {
				sum += gpuTimes[i];
			}
			double gpuTimeMean = sum / (double)curFrame;
			System.Console.Write("Average cpu time was- ");
			System.Console.Write(frameTimeMean - gpuTimeMean);
			System.Console.Write(" seconds per frame.\n");		

			double sumDiffs = 0.0;
			for (i = 0; i < curFrame; i++) {
				sumDiffs += Math.Pow((1/frames[i])-(1/frameTimeMean), 2);
			}
			double variance = sumDiffs/(double)curFrame;
			double sd = Math.Sqrt(variance);
			System.Console.Write("The standard deviation was: ");
			System.Console.Write(sd);
			System.Console.Write(" frames per second.\n");
			if (PRINT_FRAMES == true){
				System.Console.Write("--:");
				for (i = 0; i < curFrame; i++) {
					System.Console.Write(1/frames[i]);
					System.Console.Write(",");
				}
				System.Console.Write(".--");
			}		
			System.Environment.Exit(0);
		}
	}
}
