(ns ParticleBenchCJ.core
  (:require [clojure.math.numeric-tower :as math]
            [clojure.core.typed :refer [ann-record ann]])
  (:import [org.lwjgl LWJGLException BufferUtils]
           [org.lwjgl.opengl Display DisplayMode GL11 GL15])
  (:gen-class :main true))

(def ^:const  PRINT_FRAMES true)
(def ^:const  SCREEN_WIDTH 800)
(def ^:const  SCREEN_HEIGHT 600)
(def ^:const  TITLE "ParticleBench")

(def ^:const  MIN_X -80.0)
(def ^:const  MAX_X 80.0)
(def ^:const  MIN_Y -90.0)
(def ^:const  MAX_Y 50.0)
(def ^:const  MIN_DEPTH 50.0)
(def ^:const  MAX_DEPTH 250.0)

(def ^:const  START_RANGE 15.0)
(def ^:const  START_X (+ MIN_X (/ (+ MIN_X MAX_X) 2) ) )
(def ^:const  START_Y MAX_Y)
(def ^:const  START_DEPTH (+ MIN_DEPTH (/ (+ MIN_DEPTH MAX_DEPTH) 2) ))

(def ^:const  POINTS_PER_SEC 2000)
(def ^:const  MAX_INIT_VEL 7.0)
(def ^:const  MAX_LIFE 5)
(def ^:const  MAX_SCALE 4.0)

(def ^:const  WIND_CHANGE 2.0)
(def ^:const  MAX_WIND 3.0)
(def ^:const  SPAWN_INTERVAL 0.01 )
(def ^:const  RUNNING_TIME (* MAX_LIFE 5) )
(def ^:const  MAX_PTS (* RUNNING_TIME POINTS_PER_SEC))

(def ^Float init-t 0.0)
(def ^Float end-t 0.0)
(def ^Float start-t 0.0)
;(def ^Float spwn-tmr 0.0)
;(def ^Float run-tmr 0.0)
(def  frames [] ) ;(make-vector (* RUNNING_TIME 1000) 0.0) )
(def  ^Integer cur-frame 0)

(defrecord environ [ windX windY windZ])
(ann-record environ [windX :- Float, windY :- Float, windZ :- Float])

(def  ^:const ^Float grav 0.5)
(def ambient (vector-of :float 0.8 0.05 0.1 1.0))
(def diffuse (vector-of :float 1.0 1.0 1.0 1.0))
(def light-pos (vector-of :float (+ MIN_X (/ (- MAX_X MIN_X) 2) ) MAX_Y MIN_DEPTH 0.0))

(defrecord pt [ x y z vx vy vz R life is]) 
(ann-record pt [x :- Float, y :- Float, z :- Float, vx :- Float, vy :- Float, vz :- Float, R :- Float, life :- Float, is :- Boolean])

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
             -1.0 1.0 -1.0 -1.0 0.0 0.0)
  )

(defn load-cube-to-gpu []
  (def vbo (GL15/glGenBuffers))
  (GL15/glBindBuffer GL15/GL_ARRAY_BUFFER vbo)
  (let [vertexPositions (BufferUtils/createFloatBuffer (count vertex-normal-array))]
    (loop [i (count vertex-normal-array)]
      (when (> i 0)
        (. vertexPositions put (get vertex-normal-array (- (count vertex-normal-array) i))))
      (recur (- i 1))) 
    (. vertexPositions rewind)
    (GL15/glBufferData GL15/GL_ARRAY_BUFFER, vertexPositions, GL15/GL_STATIC_DRAW))
  
  (GL11/glEnableClientState GL11/GL_VERTEX_ARRAY)
  (GL11/glEnableClientState GL11/GL_NORMAL_ARRAY)
  (GL11/glVertexPointer 3 GL11/GL_FLOAT (* 6 4) 0)
  (GL11/glNormalPointer GL11/GL_FLOAT (* 6 4) (* 3 4)) 
  )

(defn testbind []
  (let [vertexPositions (BufferUtils/createFloatBuffer (count vertex-normal-array))]
    (loop [i (count vertex-normal-array)]
      (when (> i 0)
        (. vertexPositions put (get vertex-normal-array (- (count vertex-normal-array) i)))
        (recur (- i 1)))) 
    (. vertexPositions rewind)
    (loop [i (count vertex-normal-array)]
      (when (> i 0)
        (print (. vertexPositions get ))
        (recur (- i 1)))) 
    ))

(defn init []
  (Display/setDisplayMode (new DisplayMode SCREEN_WIDTH SCREEN_HEIGHT))
  (Display/setTitle TITLE)
  (Display/create)
  (GL11/glEnable GL11/GL_DEPTH_TEST)
  (GL11/glEnable GL11/GL_LIGHTING)
  
  (GL11/glClearColor 0.1 0.1 0.6 1.0)
  (GL11/glClearDepth 1)
  (GL11/glDepthFunc GL11/GL_LEQUAL)
  
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_AMBIENT ambient)
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_DIFFUSE diffuse)
  ;(GL11/glLight GL11/GL_LIGHT0 GL11/GL_POSITION light-pos)
  (GL11/glEnable GL11/GL_LIGHT0)
  
  (GL11/glViewport 0 0 SCREEN_WIDTH SCREEN_HEIGHT)
  (GL11/glMatrixMode GL11/GL_PROJECTION)
  (GL11/glLoadIdentity)
  (GL11/glFrustum -1 1 -1 1 1.0 1000.0)
  (GL11/glRotatef 20.0 1.0 0.0 0.0)
  (GL11/glMatrixMode GL11/GL_MODELVIEW)
  (GL11/glLoadIdentity)
  (GL11/glPushMatrix)
  
  )

(defn gltest-cube []
  (GL11/glBegin GL11/GL_QUADS )
  ; Top face
  (GL11/glColor3f   0.0 1.0  0.0 )  ; Green
  (GL11/glVertex3f  1.0 1.0 -1.0 )  ; Top-right of top face
  (GL11/glVertex3f -1.0 1.0 -1.0 )  ; Top-left of top face
  (GL11/glVertex3f -1.0 1.0  1.0 )  ; Bottom-left of top face
  (GL11/glVertex3f  1.0 1.0  1.0 )  ; Bottom-right of top face
  
  ; Bottom face
  (GL11/glColor3f   1.0  0.5  0.0 ) ; Orange
  (GL11/glVertex3f  1.0 -1.0 -1.0 ) ; Top-right of bottom face
  (GL11/glVertex3f -1.0 -1.0 -1.0 ) ; Top-left of bottom face
  (GL11/glVertex3f -1.0 -1.0  1.0 ) ; Bottom-left of bottom face
  (GL11/glVertex3f  1.0 -1.0  1.0 ) ; Bottom-right of bottom face
  
  ; Front face
  (GL11/glColor3f   1.0  0.0 0.0 )  ; Red
  (GL11/glVertex3f  1.0  1.0 1.0 )  ; Top-Right of front face
  (GL11/glVertex3f -1.0  1.0 1.0 )  ; Top-left of front face
  (GL11/glVertex3f -1.0 -1.0 1.0 )  ; Bottom-left of front face
  (GL11/glVertex3f  1.0 -1.0 1.0 )  ; Bottom-right of front face
  
  ; Back face
  (GL11/glColor3f   1.0  1.0  0.0 ) ; Yellow
  (GL11/glVertex3f  1.0 -1.0 -1.0 ) ; Bottom-Left of back face
  (GL11/glVertex3f -1.0 -1.0 -1.0 ) ; Bottom-Right of back face
  (GL11/glVertex3f -1.0  1.0 -1.0 ) ; Top-Right of back face
  (GL11/glVertex3f  1.0  1.0 -1.0 ) ; Top-Left of back face
  
  ; Left face
  (GL11/glColor3f   0.0  0.0  1.0)  ; Blue
  (GL11/glVertex3f -1.0  1.0  1.0)  ; Top-Right of left face
  (GL11/glVertex3f -1.0  1.0 -1.0)  ; Top-Left of left face
  (GL11/glVertex3f -1.0 -1.0 -1.0)  ; Bottom-Left of left face
  (GL11/glVertex3f -1.0 -1.0  1.0)  ; Bottom-Right of left face
  
  ; Right face
  (GL11/glColor3f   1.0  0.0  1.0)  ; Violet
  (GL11/glVertex3f  1.0  1.0  1.0)  ; Top-Right of left face
  (GL11/glVertex3f  1.0  1.0 -1.0)  ; Top-Left of left face
  (GL11/glVertex3f  1.0 -1.0 -1.0)  ; Bottom-Left of left face
  (GL11/glVertex3f  1.0 -1.0  1.0)  ; Bottom-Right of left face
  (GL11/glEnd))

(defn render-pt [apt]
  ;(print "rendering now")
  ;(printf "X: %.3f Y: %.3f Z: %.3f \n" (:x apt) (:y apt) (:z apt))
  (GL11/glMatrixMode GL11/GL_MODELVIEW)
  (GL11/glPopMatrix)
  (GL11/glPushMatrix)
  (GL11/glTranslatef (:x apt) (:y apt) (-(:z apt)) )
  (GL11/glScalef 10 10 10 )
  (gltest-cube)
  ;(GL11/glDrawArrays GL11/GL_QUADS 0 24)
  apt)
  
(ann make-new-pt [-> pt])
(defn make-new-pt []
  (let [new-pt (->pt 
                 (- (+ 0 (* (rand) START_RANGE)) (/ START_RANGE 2) ) 
                 START_Y
                 (- (+ START_DEPTH (* (rand) START_RANGE)) (/ START_RANGE 2) )
                 (* (rand) MAX_INIT_VEL)
                 (* (rand) MAX_INIT_VEL)
                 (* (rand) MAX_INIT_VEL)
                 (/ (* (rand) MAX_SCALE ) 2)
                 (* (rand) MAX_LIFE)
                 true)] new-pt))

(ann spwn-pts [Float (Vec pt) -> (Vec pt)]) 
(defn spwn-pts [secs pt-vec]
  (let [num (* secs POINTS_PER_SEC)]
    conj pt-vec (vec (repeat num (make-new-pt)))))

(ann mov-pt [Float environ pt -> pt])
(defn mov-pt [secs env apt]
  (printf "X: %.3f Y: %.3f Z: %.3f \n" (:x apt) (:y apt) (:z apt))
  ( assoc apt :x  (+ (:x apt) (* (:vx apt) secs) ))
  ( assoc apt :y  (+ (:y apt) (* (:vy apt) secs) )) 
  ( assoc apt :z  (+ (:z apt) (* (:vz apt) secs) )) 
  ( assoc apt :vx (+ (:vx apt) (* (/ 1 (:R apt)) (:windX env))))
  ( assoc apt :vx (+ (:vy apt) (* (/ 1 (:R apt)) (:windY env))))
  ( assoc apt :vx (+ (:vz apt) (* (/ 1 (:R apt)) (:windZ env))))
  ( assoc apt :vy (- (:vy apt) grav) )
  ( assoc apt :life (- (:life apt) secs) )
  ( assoc apt :is (> 0.0 (:life apt) ))
  apt
  )

(ann mov-pts [Float environ (Vec pt) -> (Vec pt)])
(defn mov-pts [secs env vec]
  (map #(mov-pt secs env %) vec))
  
(ann check-coll [pt ->])
(defn check-coll [apt]  
  (if (< (:x apt ) MIN_X) (
                            (assoc apt :x  (+ MIN_X (:R apt)) )
                            (assoc apt :vx  (* (:vx apt) -1.1)) ) false)
  (if (> (:x apt ) MAX_X) (
                            (assoc apt :x  (- MAX_X (:R apt)) )
                            (assoc apt :vx  (* (:vx apt) -1.1)) ) false)
  (if (< (:y apt ) MIN_Y) (
                            (assoc apt :y  (+ MIN_Y (:R apt)) )
                            (assoc apt :vy  (* (:vy apt) -1.1)) ) false)
  (if (> (:y apt ) MAX_Y) (
                            (assoc apt :y  (- MAX_Y (:R apt)) )
                            (assoc apt :vy  (* (:vy apt) -1.1)) ) false)
  (if (< (:z apt ) MIN_DEPTH) (
                                (assoc apt :z  (+ MIN_DEPTH (:R apt)) )
                                (assoc apt :vz  (* (:vz apt) -1.1)) ) false)
  (if (> (:z apt ) MAX_DEPTH) (
                                (assoc apt :z  (- MAX_DEPTH (:R apt)) )
                                (assoc apt :vz  (* (:vz apt) -1.1)) ) false)
  apt
  )

(ann check-colls [(Vec pt) -> (Vec pt)])
(defn check-colls [vec]
  (map check-coll vec))

(ann do-wind [env -> env])
(defn do-wind [env]
  (assoc env :windX (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE 2) ) frame-dur) (:windX env)) )
  (assoc env :windY (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE 2) ) frame-dur) (:windY env)) )
  (assoc env :windZ (+ (* (- (* (rand) WIND_CHANGE) (/ WIND_CHANGE 2) ) frame-dur) (:windZ env)) )
  (if (> (math/abs (:windX env)) MAX_WIND) (assoc env :windX (* (:windX env) -0.5) ) false)
  (if (> (math/abs (:windY env)) MAX_WIND) (assoc env :windY (* (:windY env) -0.5) ) false)
  (if (> (math/abs (:windZ env)) MAX_WIND) (assoc env :windZ (* (:windZ env) -0.5) ) false)
  env
  )

(defn end[]
  (Display/destroy))
 
(defn main-loop [pts env prev-frame-length]
  (def init-t (System/currentTimeMillis))
  (GL11/glClear GL11/GL_COLOR_BUFFER_BIT)
  (GL11/glClear GL11/GL_DEPTH_BUFFER_BIT)
  (let [new-vec (->> (spwn-pts prev-frame-length pts) (mov-pts prev-frame-length env) (check-colls) )]
    (dorun (map render-pt new-vec))
    (Display/update)
    (def end-t (System/currentTimeMillis))
    (if (> (/ (- end-t start-t) 1000) 5) (end) false)
    (recur new-vec (do-wind env) (/ (- end-t init-t) 1000))))

(defn main []
  (init)
  (def start-t (System/currentTimeMillis))
  ;(load-cube-to-gpu)
  (main-loop [] (->environ 0.5 0.1 0.2) 0.01 )) 

;This is the whole maine function from Scheme, to be implemented once the rest is working 
;(set! init-t (/ (current-inexact-milliseconds) 1000) )
;(spwn-pts 0.01 pts)
;(move-pts 0.01 pts)
;(do-wind env)
;(check-colls vec)
;(if (>= spwn-tmr *SPAWN_INTERVAL*) (begin (spwn-pts *SPAWN_INTERVAL*) (set! spwn-tmr (- spwn-tmr *SPAWN_INTERVAL*)) ) #f)
;(GL11/glClear GL11/GL_COLOR_BUFFER_BIT)
;(GL11/glClear GL11/GL_DEPTH_BUFFER_BIT)
;(render-pts vec)
;(Display/update)
;(main-loop 
;(set! end-t (/ (current-inexact-milliseconds) 1000) )
;(set! frame-dur (- end-t init-t) )
;(set! spwn-tmr (+ spwn-tmr frame-dur) )
;(set! cleanup-tmr (+ cleanup-tmr frame-dur) )
;(set! run-tmr (+ run-tmr frame-dur) )
;(if (>= run-tmr (/ *MAX_LIFE* 1000) ) (begin ( vector-set! frames cur-frame frame-dur) ( set! cur-frame (+ cur-frame 1) ) ) #f )
;(if (< run-tmr *RUNNING_TIME*) (main-loop)
;   (let ([sum 0]) (begin
;                   (for ([i (in-range 0 cur-frame)]) (set! sum (+ sum (vector-ref frames i) ) ) )
;                  (display "Average framerate was: ") (display (/ 1 (/ sum cur-frame) ) ) (display " frames per second.\n") )
;                 (if (equal? *PRINT_FRAMES* #t) (begin
;                                                     (display "--:")
;                                                    (for ([i (in-range 0 cur-frame)]) (begin (display (/ (vector-ref frames i)) ) (display ",") ) )
;                                                   (display ".--")
;                                             ) #f )
