(ns cjpb.core
  (:require [clojure.math.numeric-tower :as math])
  (:import [org.lwjgl LWJGLException BufferUtils]
           [org.lwjgl.opengl Display DisplayMode GL11 GL15 GL20])
  (:gen-class))

(set! *warn-on-reflection* true)
(set! *unchecked-math* true)
(def ^:const  PRINT_FRAMES false)
(def ^:const  SCREEN_WIDTH 800)
(def ^:const  SCREEN_HEIGHT 600)
(def ^:const  TITLE "ParticleBench")

(def ^:const ^Float MIN_X -80.0)
(def ^:const ^Float MAX_X 80.0)
(def ^:const ^Float MIN_Y -90.0)
(def ^:const  ^Float MAX_Y 50.0)
(def ^:const  ^Float MIN_DEPTH 50.0)
(def ^:const  ^Float MAX_DEPTH 250.0)

(def ^:const  ^Float START_RANGE 15.0)
(def ^:const  ^Float START_X (+ MIN_X (/ (+ MIN_X MAX_X) 2) ) )
(def ^:const  ^Float START_Y MAX_Y)
(def ^:const  ^Float START_DEPTH (+ MIN_DEPTH (/ (+ MIN_DEPTH MAX_DEPTH) 2) ))

(def ^:const  POINTS_PER_SEC 2000)
(def ^:const  ^Float MAX_INIT_VEL 7.0)
(def ^:const  MAX_LIFE 5)
(def ^:const  ^Float MAX_SCALE 4.0)

(def ^:const ^Float WIND_CHANGE 2.0)
(def ^:const ^Float MAX_WIND 3.0)
(def ^:const ^Float SPAWN_INTERVAL 0.01 )
(def ^:const ^Float RUNNING_TIME (* MAX_LIFE 5) )
(def ^:const  MAX_PTS (* RUNNING_TIME POINTS_PER_SEC))

(def ^Float init-t 0.0)
(def ^Float end-t 0.0)
(def ^Float gpu-init-t 0.0)
(def ^Float gpu-end-t 0.0)
(def ^Float frame-dur 0.0)
(def ^Float run-tmr 0.0)
(def ^Float spwn-tmr 0.0)
(def  frames (vec (repeat (* RUNNING_TIME 1000) 0)))
(def  gpu-times (vec (repeat (* RUNNING_TIME 1000) 0)))
(def  ^Integer cur-frame 0)

(def  ^:const ^Float grav 50.0)
(def ambient (vector-of :float 0.8 0.05 0.1 1.0))
(def diffuse (vector-of :float 1.0 1.0 1.0 1.0))
(def light-pos (vector-of :float (+ MIN_X (/ (- MAX_X MIN_X) 2) ) MAX_Y MIN_DEPTH 0.0))

(defrecord environ [ ^Float windX ^Float windY ^Float windZ])

(definterface IPt
  (^Double gx []) (^Double gy []) (^Double gz []) (^Double gvx []) (^Double gvy []) (^Double gvz []) (^Double gR []) (^Double glife []) (^Boolean gis [])
  (sx [^Double v]) (sy [^Double v]) (sz [^Double v]) (svx [^Double v]) (svy [^Double v]) (svz [^Double v]) (sR [^Double v]) (slife [^Double v]) (^Boolean sis [^Boolean v]))

(deftype Particle [^:unsynchronized-mutable ^Double x ^:unsynchronized-mutable ^Double y ^:unsynchronized-mutable ^Double z 
                   ^:unsynchronized-mutable ^Double vx ^:unsynchronized-mutable ^Double vy ^:unsynchronized-mutable ^Double vz 
                   ^:unsynchronized-mutable ^Double R ^:unsynchronized-mutable ^Double life ^:unsynchronized-mutable ^Boolean is]
  IPt
  (gx [_] x)(gy [_] y)(gz [_] z)(gvx [_] vx)(gvy [_] vy)(gvz [_] vz)(gR [_] R)(glife [_] life)(gis [_] is)
  (sx [this v] (set! x v)) (sy [this v] (set! y v))(sz [this v] (set! z v))
  (svx [this v] (set! vx v)) (svy [this v] (set! vy v))(svz [this v] (set! vz v))
  (sR [this v] (set! R v))(slife [this v] (set! life v))(sis [this v] (set! is v))) 

(definterface ISlice
  (^Long gLen [])
  (sLen [^Long x])
  (^cjpb.core.Particle gPt [^Long n])
  (sPt [^Long n ^cjpb.core.Particle pt] ))

(deftype PSlice [^"[Ljava.lang.Object;" pts ^:unsynchronized-mutable ^Long len]
  ISlice
  (gLen [_] len)
  (sLen [this new-len] (set! len new-len))
  (gPt [this n] (aget pts n))
  (sPt [this n pt] (aset pts n pt)))

(def tst (Particle. (float 0) (float 0) (float 0) (float 0) (float 0) (float 0) (float 0) (float 0) true))
(def aenv (->environ -2 0 -1)) 
(def tslice (PSlice. (make-array Object MAX_PTS) 0))

(defn test-fn [^PSlice slice]
  (print (.gLen slice))
  )

(defn render-pt [^cjpb.core.Particle apt]
  (if (.gis apt) (do
                   (GL11/glPopMatrix)
                   (GL11/glPushMatrix)
                   (GL11/glTranslatef (float (.gx apt)) (float (.gy apt)) (float (- 0 (.gz apt))) )
                   (GL11/glScalef (* (float (.gR apt)) (float 2.0)) (* (float (.gR apt)) (float 2.0)) (* (float (.gR apt)) (float 2.0)) )
                   (GL11/glDrawArrays GL11/GL_QUADS (int 0) (int 24))
                   apt)) false)

(defn new-pt [^PSlice pts]
  (.sPt pts (.gLen pts)  (Particle. 
                               (- (+ (float 0.0) (* (float (rand)) START_RANGE)) (/ START_RANGE (float 2.0)) ) 
                               START_Y
                               (- (+ START_DEPTH (* (float (rand)) START_RANGE)) (/ START_RANGE (float 2.0)) )
                               (* (float (rand)) MAX_INIT_VEL)
                               (* (float (rand)) MAX_INIT_VEL)
                               (* (float (rand)) MAX_INIT_VEL)
                               (/ (* (float (rand)) MAX_SCALE ) (float 2.0))
                               (* (float (rand)) MAX_LIFE)
                               true)
    )
  (.sLen pts (+ (.gLen pts) (int 1))))

(defn spwn-pts [^Float secs ^PSlice pts]
  (if (> spwn-tmr SPAWN_INTERVAL) (do
  (let [num (* SPAWN_INTERVAL POINTS_PER_SEC)]
    (dotimes [not-used num] (new-pt pts) ))
   (def spwn-tmr (- spwn-tmr SPAWN_INTERVAL) ))
   false)
  pts)

(defn mov-pt [^Float secs ^environ env ^Long pos ^PSlice pts]
  (let [apt (.gPt pts pos)]
    (if (.gis apt) (do
    (.sx (.gPt pts pos) (+ (.gx apt) (* (.gvx apt) secs)) )
    (.sy (.gPt pts pos) (- (+ (.gy apt) (* (.gvy apt) secs) ) (* grav secs)))
    (.sz (.gPt pts pos) (+ (.gz apt) (* (.gvz apt) secs) ))
    (.svx (.gPt pts pos) (+ (.gvx apt) (* (/ (float 1.0) (.gR apt)) (:windX env))))
    (.svy (.gPt pts pos) (+ (.gvy apt) (* (/ (float 1.0) (.gR apt)) (:windY env))))
    (.svz (.gPt pts pos) (+ (.gvz apt) (* (/ (float 1.0) (.gR apt)) (:windZ env))))
    (.slife (.gPt pts pos) (- (.glife apt) secs)) 
    (.sis (.gPt pts pos) (< (float 0.0) (.glife apt) ))))))


(defn mov-pts [^Float secs ^environ env ^PSlice pts]
  (dotimes [i (- (.gLen pts) 1)] (mov-pt secs env i pts))
  pts) 

(defn check-coll [^Long pos ^PSlice pts]
  (let [apt (.gPt pts pos)]
    (if (.gis apt)
        (cond 
            (< (.gx apt ) MIN_X) (do (.sx (.gPt pts pos) (+ MIN_X (.gR apt))) (.svx (.gPt pts pos) (* (.gvx apt) (float -1.1)))  ) 
            (> (.gx apt ) MAX_X) (do (.sx (.gPt pts pos) (- MAX_X (.gR apt))) (.svx (.gPt pts pos) (* (.gvx apt) (float -1.1)))  )
            (< (.gy apt ) MIN_Y) (do (.sy (.gPt pts pos) (+ MIN_Y (.gR apt))) (.svy (.gPt pts pos) (* (.gvy apt) (float -1.1)))  ) 
            (> (.gy apt ) MAX_Y) (do (.sy (.gPt pts pos) (- MAX_Y (.gR apt))) (.svy (.gPt pts pos) (* (.gvy apt) (float -1.1)))  )
            (< (.gz apt ) MIN_DEPTH) (do (.sz (.gPt pts pos) (+ MIN_DEPTH (.gR apt))) (.svz (.gPt pts pos) (* (.gvz apt) (float -1.1)))  ) 
            (> (.gz apt ) MAX_DEPTH) (do (.sz (.gPt pts pos) (- MAX_DEPTH (.gR apt))) (.svz (.gPt pts pos) (* (.gvz apt) (float -1.1)))  )
            ))))

(defn check-colls [^PSlice pts]
  (dotimes [i (- (.gLen pts) 1)] (check-coll i pts) )
  pts)

(defn render-pts [^PSlice pts]
  (dotimes [i (- (.gLen pts) 1)] (render-pt (.gPt pts i) ))
  (Display/update)
  pts)

(def vertex-normal-array
  (vector-of :float 
             -1.0 -1.0 1.0 0.0 0.0 1.0
             1.0 -1.0 1.0 0.0 0.0 1.0
             1.0 1.0 1.0 0.0 0.0 1.0
             -1.0 1.0 1.0 0.0 0.0 1.0
             -1.0 -1.0 -1.0 0.0 0.0 -1.0
             -1.0 1.0 -1.0 0.0 0.0 -1.0
             1.0 1.0 -1.0 0.0 0.0 -1.0
             1.0 -1.0 -1.0 0.0 0.0 -1.0
             -1.0 1.0 -1.0 0.0 1.0 0.0
             -1.0 1.0 1.0 0.0 1.0 0.0
             1.0 1.0 1.0 0.0 1.0 0.0
             1.0 1.0 -1.0 0.0 1.0 0.0
             -1.0 -1.0 -1.0 0.0 -1.0 0.0
             1.0 -1.0 -1.0 0.0 -1.0 0.0
             1.0 -1.0 1.0 0.0 -1.0 0.0
             -1.0 -1.0 1.0 0.0 -1.0 0.0
             1.0 -1.0 -1.0 1.0 0.0 0.0
             1.0 1.0 -1.0 1.0 0.0 0.0
             1.0 1.0 1.0 1.0 0.0 0.0
             1.0 -1.0 1.0 1.0 0.0 0.0
             -1.0 -1.0 -1.0 -1.0 0.0 0.0
             -1.0 -1.0 1.0 -1.0 0.0 0.0
             -1.0 1.0 1.0 -1.0 0.0 0.0
             -1.0 1.0 -1.0 -1.0 0.0 0.0))

(defn load-cube-to-gpu []
  (def vbo (GL15/glGenBuffers))
  (GL15/glBindBuffer GL15/GL_ARRAY_BUFFER vbo)
  (let [vertexPositions (BufferUtils/createFloatBuffer (count vertex-normal-array))]
    (loop [i (count vertex-normal-array)]
      (when (> i 0)
        (. vertexPositions put (float (get vertex-normal-array (- (count vertex-normal-array) i))))
        (recur (- i 1)))) 
    (. vertexPositions rewind)
    (GL15/glBufferData GL15/GL_ARRAY_BUFFER, vertexPositions, GL15/GL_STATIC_DRAW))
  (GL11/glEnableClientState GL11/GL_VERTEX_ARRAY)
  (GL11/glEnableClientState GL11/GL_NORMAL_ARRAY)
  (GL11/glVertexPointer 3 GL11/GL_FLOAT (* 6 4) 0)
  (GL11/glNormalPointer GL11/GL_FLOAT (* 6 4) (* 3 4))
  (GL11/glMatrixMode GL11/GL_MODELVIEW)) 

(defn init []
  (Display/setDisplayMode (new DisplayMode SCREEN_WIDTH SCREEN_HEIGHT))
  (Display/setTitle TITLE)
  (Display/create)
  (GL11/glEnable GL11/GL_DEPTH_TEST)
  (GL11/glEnable GL11/GL_LIGHTING)
  
  (GL11/glClearColor 0.1 0.1 0.6 1.0)
  (GL11/glClearDepth (int 1))
  (GL11/glDepthFunc GL11/GL_LEQUAL)
  
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_AMBIENT ambient)
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_DIFFUSE diffuse)
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_POSITION light-pos)
  (GL11/glEnable GL11/GL_LIGHT0)
  
  (GL11/glViewport (int 0) (int 0) (int SCREEN_WIDTH) (int SCREEN_HEIGHT))
  (GL11/glMatrixMode GL11/GL_PROJECTION)
  (GL11/glLoadIdentity)
  ;(GL11/glFrustum -1  1  -1  1  1  1000)
  (GL11/glFrustum (int -1) (int 1) (int -1) (int 1) (int 1) (int 1000))
  (GL11/glRotatef (float 20.0) (float 1.0) (float 0.0) (float 0.0))
  (GL11/glMatrixMode GL11/GL_MODELVIEW)
  (GL11/glLoadIdentity)
  (GL11/glPushMatrix))

(defn end[]
  (Display/destroy))

(defn do-wind [^environ env ^Float frame-dur]
  (->environ (if (> (math/abs (:windX env)) MAX_WIND)
               (* (:windX env) (float -0.5))
               (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE (float 2.0)) ) frame-dur) (:windX env)))
             (if (> (math/abs (:windY env)) MAX_WIND)
               (* (:windY env) (float -0.5))
               (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE (float 2.0)) ) frame-dur) (:windY env)))
             (if (> (math/abs (:windZ env)) MAX_WIND)
               (* (:windZ env) (float -0.5))
               (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE (float 2.0)) ) frame-dur) (:windZ env)))))

(defn set-timer [^Float tmr ^PSlice pts] (def tmr (System/currentTimeMillis)) pts)

(defn main-loop [^PSlice pts env prev-frame-length]
  (def init-t (System/currentTimeMillis))
  (GL11/glClear (bit-or GL11/GL_COLOR_BUFFER_BIT GL11/GL_DEPTH_BUFFER_BIT))
  (->> (spwn-pts prev-frame-length pts) (mov-pts prev-frame-length env) (check-colls)); (set-timer gpu-init-t) (render-pts) )
  (def gpu-init-t (System/currentTimeMillis))
  (render-pts pts)
  (def gpu-end-t (System/currentTimeMillis))
  (def end-t (System/currentTimeMillis))
  (def ^Float frame-dur (/ (- end-t init-t) (float 1000)) )
  (def run-tmr (+ run-tmr frame-dur) )
  (def spwn-tmr (+ spwn-tmr frame-dur) )
  (if (>= run-tmr (/ MAX_LIFE 1000) ) ( do
                                        (def frames (assoc frames cur-frame frame-dur))
                                        (def gpu-times (assoc gpu-times cur-frame (/ (- gpu-end-t gpu-init-t) (float 1000))))
                                        (def cur-frame (inc cur-frame))) false)
  (if (< run-tmr RUNNING_TIME) 
    (recur pts (do-wind env frame-dur) frame-dur)
    (do 
      (end)
      (def mean-frame-time (/ (->> (take cur-frame frames) (reduce +)) cur-frame))
      (def mean-gpu-time (/ (->> (take cur-frame gpu-times) (reduce +)) cur-frame))
      (printf "Average framerate was: %.6f frames per second.\n", (float (/ 1 mean-frame-time)))
      (printf "Average cpu time was- %.6f seconds per frame.\n", (float (- mean-frame-time mean-gpu-time)))
      (if PRINT_FRAMES (do 
                         (print "--:")
                         (dorun (map #(printf "%.6f," (float %)) (take cur-frame frames)))
                         (print ".--"))
        false))))

(defn -main []
  (init)
  (load-cube-to-gpu)
  (main-loop tslice (->environ -2 0 -1) 0.01 ))
