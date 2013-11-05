import javax.media.opengl.GLAutoDrawable;
import javax.media.opengl.GLEventListener;
import javax.media.opengl.GLProfile;
import javax.media.opengl.GLCapabilities;
import javax.media.opengl.awt.GLCanvas;
import com.jogamp.opengl.util.*;
import javax.swing.JFrame;

import java.awt.BorderLayout;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;

import javax.media.opengl.GL;
import javax.media.opengl.GL2;
import javax.media.opengl.glu.GLU;

import com.jogamp.common.nio.Buffers;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.lang.System;

public class Java {

	public static void main( String [] args ) {
		GLProfile.initSingleton();
		GLProfile glprofile = GLProfile.getDefault();
		GLCapabilities glcapabilities = new GLCapabilities( glprofile );
		final GLCanvas glcanvas = new GLCanvas( glcapabilities );

		glcanvas.addGLEventListener( new GLEventListener() {
         	   
			@Override
			public void reshape( GLAutoDrawable glautodrawable, int x, int y, int width, int height ) {
			}
        	    
			@Override
			public void init( GLAutoDrawable glautodrawable ) {
				Globals.initScene( glautodrawable.getGL().getGL2() );
				Globals.loadCubeToGPU( glautodrawable.getGL().getGL2() );
			}
        	    
			@Override
			public void dispose( GLAutoDrawable glautodrawable ) {

			}
        	    
			@Override
			public void display( GLAutoDrawable glautodrawable ) {
				Globals.initT = System.currentTimeMillis();
				Globals.movPts(Globals.frameDur);
				Globals.doWind();
				if (Globals.spwnTmr >= Globals.SPAWN_INTERVAL) {
					Globals.spwnPts(Globals.SPAWN_INTERVAL);
					Globals.spwnTmr -= Globals.SPAWN_INTERVAL;
				}
				if (Globals.cleanupTmr >= (double)(Globals.MAX_LIFE)/1000) {
					Globals.cleanupPtPool();
					Globals.cleanupTmr = 0;
				}
				Globals.checkColls();
				glautodrawable.getGL().getGL2().glClear(GL.GL_COLOR_BUFFER_BIT | GL.GL_DEPTH_BUFFER_BIT);
		
				Globals.renderPts(glautodrawable.getGL().getGL2());
		
				Globals.endT = System.currentTimeMillis();
				Globals.frameDur = (Globals.endT-Globals.initT)/1000;
				Globals.spwnTmr += Globals.frameDur;
				Globals.cleanupTmr += Globals.frameDur;
				Globals.runTmr += Globals.frameDur;
				if (Globals.runTmr > Globals.MAX_LIFE/1000) { 
					Globals.frames[Globals.curFrame] = Globals.frameDur;
					Globals.curFrame += 1;			
				}
				
				if (Globals.runTmr >= Globals.RUNNING_TIME) {
					double sum = 0;
					int i = 0;
					for (i = 0; i < Globals.curFrame; i++) {
						sum += Globals.frames[i];
					}
					double mean = sum / (double)Globals.curFrame;
					System.out.println("Average framerate was: ");
					System.out.println(1/mean);
					System.out.println(" frames per second.\n");		
					double sumDiffs = 0.0;
					for (i = 0; i < Globals.curFrame; i++) {
						sumDiffs += Math.pow((1/Globals.frames[i])-(1/mean), 2);
					}
					double variance = sumDiffs/(double)Globals.curFrame;
					double sd = Math.sqrt(variance);
					System.out.println("The standard deviation was: ");
					System.out.println(sd);
					System.out.println(" frames per second.\n");
				}
				System.out.println("Framedone"); 
			}
		});
		final JFrame jframe = new JFrame( Globals.TITLE ); 
		jframe.addWindowListener( new WindowAdapter() {
			public void windowClosing( WindowEvent windowevent ) {
				jframe.dispose();
				System.exit( 0 );
			}
		});
        	jframe.getContentPane().add( glcanvas, BorderLayout.CENTER );
        	jframe.setSize( Globals.WIDTH, Globals.HEIGHT );
        	jframe.setVisible( true );

		FPSAnimator animator = new FPSAnimator(glcanvas, 60);
		animator.start();
	}
}

class Pt {
	public float X; public float Y; public float Z; public float VX; public float VY; public float VZ; public float R; public float Life; 
	public boolean alive;
}

class Vertex {
	public float[] pos = new float[3];
	public float[] normal = new float[3];
}

class Globals {
	public static final String TITLE = "ParticleBench";
	public static final int WIDTH = 800;
	public static final int HEIGHT = 600;

	public static final int MIN_X = -80;
	public static final int MAX_X = 80;
	public static final int MIN_Y = -90;
	public static final int MAX_Y = 50;
	public static final int MIN_DEPTH = 50;
	public static final int MAX_DEPTH = 250;

	public static final int START_RANGE = 15;
	public static final int START_X = (MIN_X + (MIN_X+MAX_X)/2);
	public static final int START_Y = MAX_Y;
	public static final int START_DEPTH = (MIN_DEPTH + (MIN_DEPTH+MAX_DEPTH)/2);

	public static final int POINTS_PER_SEC = 2000;
	public static final int MAX_INIT_VEL = 7;
	public static final int MAX_LIFE = 5000;
	public static final int MAX_SCALE = 4;

	public static final int WIND_CHANGE = 2000;
	public static final int MAX_WIND = 3;
	public static final double SPAWN_INTERVAL = 0.01 ;
	public static final int RUNNING_TIME = ((MAX_LIFE / 1000) * 5);
	public static final int MAX_PTS = (RUNNING_TIME * POINTS_PER_SEC);

	public static final float[] ambient = {0.8f, 0.05f, 0.1f, 1f};
	public static final float[] diffuse = {1.0f, 1.0f, 1.0f, 1f};
	public static final float[] lightPos = {MIN_X + (MAX_X-MIN_X)/2, MAX_Y, MIN_DEPTH, 0};

	public static double[] frames = new double[RUNNING_TIME * 1000];
	public static int curFrame = 0;
	public static Pt[] Pts = new Pt[MAX_PTS];
	public static Vertex[] Vertices = new Vertex[24];

	public static int gVBO = 0;

	public static double windX = 0; 
	public static double windY = 0;
	public static double windZ = 0;
	public static double grav = 0.5;

	public static double initT = 0;
	public static double endT = 0;
	public static double frameDur = 0;
	public static double spwnTmr = 0;
	public static double cleanupTmr = 0;
	public static double runTmr = 0;

	public static int numPts = 0;      
	public static int minPt = 0;       
	public static int seed = 1234569;

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
	
	public static void loadCubeToGPU(GL2 gl2){
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
		
		IntBuffer buf = Buffers.newDirectIntBuffer(1);
		gl2.glGenBuffers(1, buf);
		gVBO = buf.get();
		
		FloatBuffer data = Buffers.newDirectFloatBuffer(Vertices.length * 6);

		for (int i = 0; i < Vertices.length; i++) {
			data.put(Vertices[i].pos[0]);
			data.put(Vertices[i].pos[1]);
			data.put(Vertices[i].pos[2]);

			data.put(Vertices[i].normal[0]);
			data.put(Vertices[i].normal[1]);
			data.put(Vertices[i].normal[2]);
		}
      		data.rewind();
		
		int bytesPerFloat = Float.SIZE / Byte.SIZE;
		int numBytes = data.capacity() * bytesPerFloat;

		gl2.glBindBuffer( GL.GL_ARRAY_BUFFER, gVBO );
		gl2.glBufferData( GL.GL_ARRAY_BUFFER, numBytes, data, GL.GL_STATIC_DRAW );
		gl2.glBindBuffer(GL.GL_ARRAY_BUFFER, 0);
	}

	public static int rand(){
    		seed ^= seed << 13;
	    	seed ^= seed >>> 17;
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
			Pts[i].VY -= grav;
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
		if (Math.abs(windX) > MAX_WIND) {
			windX *= -0.5;
		}
		if (Math.abs(windY) > MAX_WIND) {
			windY *= -0.5;
		}
		if (Math.abs(windZ) > MAX_WIND) {
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

	public static void initScene(GL2 gl2) {
		gl2.glEnable(GL.GL_DEPTH_TEST);
		gl2.glEnable(GL2.GL_LIGHTING);
	
		gl2.glClearColor(0.1f, 0.1f, 0.6f, 1.0f);
		gl2.glClearDepth(1);
		gl2.glDepthFunc(GL.GL_LEQUAL);
	
		FloatBuffer data = Buffers.newDirectFloatBuffer(4);
		for (int i = 0; i < 4; i++) {
			data.put(ambient[i]);
		}
      		data.rewind();
		gl2.glLightfv(GL2.GL_LIGHT0, GL2.GL_AMBIENT, data);
		data.rewind();
		for (int i = 0; i < 4; i++) {
			data.put(diffuse[i]);
		}
		gl2.glLightfv(GL2.GL_LIGHT0, GL2.GL_DIFFUSE, data);
		data.rewind();
		for (int i = 0; i < 4; i++) {
			data.put(lightPos[i]);
		}
		gl2.glLightfv(GL2.GL_LIGHT0, GL2.GL_POSITION, data);
		gl2.glEnable(GL2.GL_LIGHT0);
	
		gl2.glViewport(0, 0, WIDTH, HEIGHT);
		gl2.glMatrixMode(GL2.GL_PROJECTION);
		gl2.glLoadIdentity();
		gl2.glFrustum(-1, 1, -1, 1, 1.0, 1000.0);
		gl2.glRotatef(20, 1, 0, 0);
		gl2.glMatrixMode(GL2.GL_MODELVIEW);
		gl2.glLoadIdentity();
		gl2.glPushMatrix();
		
		return;
	}
	public static void renderPts(GL2 gl2){
		gl2.glEnableClientState( GL2.GL_VERTEX_ARRAY );
		gl2.glEnableClientState( GL2.GL_NORMAL_ARRAY );	
		gl2.glVertexPointer( 3, GL.GL_FLOAT, 24, null );	
		gl2.glNormalPointer( GL.GL_FLOAT, 12, null);	
		gl2.glMatrixMode(GL2.GL_MODELVIEW);
	
		for (int i = minPt; i < numPts; i++) {
			if (Pts[i].alive == false) {
				continue;
			}
			Pt pt = Pts[i];
			gl2.glPopMatrix();
			gl2.glPushMatrix();
			gl2.glTranslatef(pt.X, pt.Y, -pt.Z);
			gl2.glScalef(pt.R * 2, pt.R*2, pt.R*2);
			System.out.println("Preparing to draw");
			gl2.glDrawArrays( GL2.GL_QUADS, 0, 24 );
			System.out.println("Drawn");	
		}
		gl2.glDisableClientState( GL2.GL_VERTEX_ARRAY );
		gl2.glDisableClientState( GL2.GL_NORMAL_ARRAY );	

	}
}
