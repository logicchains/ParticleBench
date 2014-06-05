(ns cjpb.core
  (:require [clojure.math.numeric-tower :as math])
  (:import [org.lwjgl LWJGLException BufferUtils]
           [org.lwjgl.opengl Display DisplayMode GL11 GL15 GL20])
  (:gen-class))

(set! *warn-on-reflection* true)
(set! *unchecked-math* true)
(def ^:const PRINT_FRAMES false)
(def ^:const SCREEN_WIDTH 800)
(def ^:const SCREEN_HEIGHT 600)
(def ^:const TITLE "ParticleBench")

(def ^:const ^double MIN_X -80.0)
(def ^:const ^double MAX_X 80.0)
(def ^:const ^double MIN_Y -90.0)
(def ^:const ^double MAX_Y 50.0)
(def ^:const ^double MIN_DEPTH 50.0)
(def ^:const ^double MAX_DEPTH 250.0)

(def ^:const ^double START_RANGE 15.0)
(def ^:const ^double START_X (+ MIN_X (/ (+ MIN_X MAX_X) 2) ) )
(def ^:const ^double START_Y MAX_Y)
(def ^:const ^double START_DEPTH (+ MIN_DEPTH (/ (+ MIN_DEPTH MAX_DEPTH) 2) ))

(def ^:const ^long POINTS_PER_SEC 2000)
(def ^:const ^double MAX_INIT_VEL 7.0)
(def ^:const ^long MAX_LIFE 4)
(def ^:const ^double MAX_SCALE 4.0)

(def ^:const ^double WIND_CHANGE 2.0)
(def ^:const ^double MAX_WIND 3.0)
(def ^:const ^double SPAWN_INTERVAL 0.01 )
(def ^:const ^long RUNNING_TIME (* MAX_LIFE 4) )
(def ^:const  ^long MAX_PTS (* RUNNING_TIME POINTS_PER_SEC))

(def ^Long cur-frame (long 0))
(def frames (vec (repeat (* RUNNING_TIME 1000) 0)))
(def gpu-times (vec (repeat (* RUNNING_TIME 1000) 0)))

(def  ^:const ^double grav 50.0)
(def ambient (vector-of :double 0.8 0.05 0.1 1.0))
(def diffuse (vector-of :double 1.0 1.0 1.0 1.0))
(def light-pos (vector-of :double (+ MIN_X (/ (- MAX_X MIN_X) 2) ) MAX_Y MIN_DEPTH 0.0))

(defrecord environ [^double windX ^double windY ^double windZ])
(defrecord timers [^double init-t ^double end-t ^double gpu-init-t ^double gpu-end-t
                   ^double frame-dur ^double run-tmr ^double spwn-tmr])
  
(deftype pt [^double x ^double y ^double z ^double vx ^double vy ^double vz
             ^double R ^double life ^boolean is])

(defrecord state [^environ env ^timers tmrs ^clojure.lang.PersistentVector pts ^int cur-frame])

(defn init-state []
  (->state (->environ (long -2.0) (double 0.0) (double -1.0)) 
                      (->timers (long 0) (long 0) (long 0) (long 0) (long 0) (double 0.0) (double 0.0)) [] (long 0)))

(defn render-pt [^pt apt]
                   (GL11/glPopMatrix)
                   (GL11/glPushMatrix)
                   (GL11/glTranslatef (double (.x apt)) (double (.y apt)) (double (- 0 (.z apt))) )
                   (GL11/glScalef (* (double (.R apt)) (double 2.0)) (* (double (.R apt)) (double 2.0)) (* (double (.R apt)) (double 2.0)) )
                   (GL11/glDrawArrays GL11/GL_QUADS (int 0) (int 24))
                   apt)

(defn make-pts [^clojure.lang.PersistentVector pts ^long num]
  (let [t-pts (transient pts)]
    (dotimes [not-used num] 
      (conj! t-pts (->pt 
                     (- (+ (double 0.0) (* (double (rand)) START_RANGE)) (/ START_RANGE (double 2.0)) ) 
                     START_Y
                     (- (+ START_DEPTH (* (double (rand)) START_RANGE)) (/ START_RANGE (double 2.0)) )
                     (* (double (rand)) MAX_INIT_VEL)
                     (* (double (rand)) MAX_INIT_VEL)
                     (* (double (rand)) MAX_INIT_VEL)
                     (/ (* (double (rand)) MAX_SCALE ) (double 2.0))
                     (* (double (rand)) MAX_LIFE)
                     true)))
    (persistent! t-pts)))

(defn spwn-pts [^double secs ^state state]
  (let [^timers tmrs (:tmrs state) ^clojure.lang.PersistentVector pts (:pts state)]
    (assoc state :pts
            (if (> (:spwn-tmr tmrs) SPAWN_INTERVAL)
              (make-pts pts (* SPAWN_INTERVAL POINTS_PER_SEC))
            pts))))

(defn mov-pt [^double secs ^environ env ^pt apt]
    (->pt
    (+ ^double (.x apt) ^double (* ^double (.vx apt) secs)) 
    (- ^double (+ (.y apt) ^double (* ^double (.vy apt) secs) ) (* grav secs))
    (+ ^double (.z apt) ^double (* ^double (.vz apt) secs) )
    (+ ^double (.vx apt) ^double (/ ^double (.windX env) ^double (.R apt)))
    (+ ^double (.vy apt) ^double (/ ^double (.windY env) ^double (.R apt)))
    (+ ^double (.vz apt) ^double (/ ^double (.windZ env) ^double (.R apt)))
    ^double (.R apt)
    (- ^double (.life apt) secs)
    (if (> (double 0.0) ^double (.life apt)) false true )))

(defn mov-pts [^double secs ^state state]
  (let [^clojure.lang.PersistentVector pts (:pts state) ^environ env (:env state) ^clojure.lang.PersistentVector t-pts (transient pts)]
    (dotimes [i (- (count pts) (long 1))] 
      (assoc! t-pts i ^pt (mov-pt secs env (nth pts i))))           
    (assoc state :pts (persistent! t-pts)))) 

(defn bind-pt [^pt apt]
  (let [x (if (< (.x apt) MIN_X) 
            (+ MIN_X (.R apt))
               (if (> (.x apt) MAX_X)
                 (- MAX_X (.R apt)) (.x apt)))
        y (if (< (.y apt) MIN_Y) 
            (+ MIN_Y (.R apt))
               (if (> (.y apt) MAX_Y)
                 (- MAX_Y (.R apt)) (.y apt)))
        z (if (< (.z apt) MIN_DEPTH) 
            (+ MIN_DEPTH (.R apt))
               (if (> (.z apt) MAX_DEPTH)
                 (- MAX_DEPTH (.R apt)) (.z apt)))
        vx (if (or (< (.x apt) MIN_X) (> (.x apt) MAX_X)) (* (.vx apt) -1.1) (.vx apt))
        vy (if (or (< (.y apt) MIN_Y) (> (.y apt) MAX_Y)) (* (.vy apt) -1.1) (.vy apt))
        vz (if (or (< (.z apt) MIN_DEPTH) (> (.z apt) MAX_DEPTH)) (* (.vz apt) -1.1) (.vz apt))]
    (->pt x y z vx vy vz (.R apt) (.life apt) (.is apt))))

(defn check-coll [^pt apt]
  (if (or (< (.x apt) MIN_X) (> (.x apt) MAX_X)
          (< (.y apt) MIN_Y) (> (.y apt) MAX_Y)
          (< (.z apt) MIN_DEPTH) (> (.z apt) MAX_DEPTH))
    (bind-pt apt)
    apt))

(defn check-colls [^state state]
  (let [t-pts (transient (:pts state))]
    (dotimes [i (- (count t-pts) (int 1))] 
      (assoc! t-pts i (check-coll (nth t-pts i)) ))
    (assoc state :pts (persistent! t-pts))))

(defn render-pts [^state state]
  (let [pts (:pts state)] 
    (dotimes [i (- (count pts) (int 1))] (render-pt (nth pts i) ))
    (Display/update)
    state))

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
        (. vertexPositions put (double (get vertex-normal-array (- (count vertex-normal-array) i))))
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
  (GL11/glRotatef (double 20.0) (double 1.0) (double 0.0) (double 0.0))
  (GL11/glMatrixMode GL11/GL_MODELVIEW)
  (GL11/glLoadIdentity)
  (GL11/glPushMatrix))

(defn end[]
  (Display/destroy))

(defmacro bind-wind-axis [getter env frame-dur] `(if (> (math/abs (~getter ~env)) MAX_WIND)
                                     (* (~getter ~env) (double -0.5))
                                     (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE (double 2.0)) ) ~frame-dur) (~getter ~env))))

(defn do-wind [^state state ^double frame-dur]
  (let [^environ env (:env state)]
    (assoc state :env  
            (->environ (bind-wind-axis :windX env frame-dur) (bind-wind-axis :windY env frame-dur) (bind-wind-axis :windZ env frame-dur)))))
  
(defn set-timer [^double tmr ^clojure.lang.PersistentVector pts] (def tmr (System/currentTimeMillis)) pts)

(defn filter-dead [^state state]
  (let [pts (:pts state)]
    (assoc state :pts (vec (filter (fn [^pt x] (.is x))
                                   pts)))))

(defn main-loop [^state state prev-frame-length] 
  (let [init-t (System/currentTimeMillis) ^timers tmrs (:tmrs state)]
    (GL11/glClear (bit-or GL11/GL_COLOR_BUFFER_BIT GL11/GL_DEPTH_BUFFER_BIT))
    (let [^state state (->> (spwn-pts prev-frame-length state) (mov-pts prev-frame-length) (filter-dead) (check-colls) (render-pts))]
      (let [gpu-init-t (System/currentTimeMillis)]
        (let [gpu-end-t (System/currentTimeMillis)
              end-t (System/currentTimeMillis)
              frame-dur (/ (double ^long (- end-t init-t)) (double 1000.0))
              run-tmr (+ ^double (:run-tmr tmrs) frame-dur)
              spwn-tmr (+ ^double (:spwn-tmr tmrs) frame-dur)]
          (if (>= run-tmr (/ MAX_LIFE (double 1000.0)) ) ( do
                                                          (def frames (assoc frames cur-frame frame-dur))
                                                          (def gpu-times (assoc gpu-times cur-frame (/ (double ^long (- gpu-end-t gpu-init-t)) (double 1000.0))))
                                                          (def ^long cur-frame (inc cur-frame))) false)
          (if (< run-tmr RUNNING_TIME)
            (let [^timer new-tmrs (->timers init-t end-t gpu-init-t gpu-end-t frame-dur run-tmr spwn-tmr)]
              (recur (assoc (do-wind state frame-dur) :tmrs new-tmrs) frame-dur))
            (do 
              (end)
              (def mean-frame-time (/ (->> (take cur-frame frames) (reduce +)) cur-frame))
              (def mean-gpu-time (/ (->> (take cur-frame gpu-times) (reduce +)) cur-frame))
              (printf "Average framerate was: %.6f frames per second.\n", (double (/ 1 mean-frame-time)))
              (printf "Average cpu time was- %.6f seconds per frame.\n", (double (- mean-frame-time mean-gpu-time)))
              (if PRINT_FRAMES (do 
                                 (print "--:")
                                 (dorun (map #(printf "%.6f," (double %)) (take cur-frame frames)))
                                 (print ".--"))
                false))))))))

(defn -main []
  (init)
  (load-cube-to-gpu)
  (main-loop (init-state) (double 0.01) ))
