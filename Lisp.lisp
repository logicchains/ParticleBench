(ql:quickload "cl-opengl")
(ql:quickload "cl-glfw3")
(defpackage #:particle-bench
  (:nicknames :pb)
  (:use #:cl #:glfw))

(declaim (optimize (speed 3) (space 0) (debug 0)))
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))

(in-package #:particle-bench)
(export '(run))

(def-key-callback key-callback (window key scancode action mod-keys)
  (when (and (eq key :escape) (eq action :press))
    (set-window-should-close)))

(defparameter *PRINT_FRAMES* t)
(defparameter *SCREEN_WIDTH* 800)
(defparameter *SCREEN_HEIGHT* 600)
(defparameter *TITLE* "ParticleBench")

(defparameter *MIN_X* -80.0)
(defparameter *MAX_X* 80.0)
(defparameter *MIN_Y* -90.0)
(defparameter *MAX_Y* 50.0)
(defparameter *MIN_DEPTH* 50.0)
(defparameter *MAX_DEPTH* 250.0)

(defparameter *START_RANGE* 15.0)
(defparameter *START_X* (+ *MIN_X* (/ (+ *MIN_X* *MAX_X*) 2) ) )
(defparameter *START_Y* *MAX_Y*)
(defparameter *START_DEPTH* (+ *MIN_DEPTH* (/ (+ *MIN_DEPTH* *MAX_DEPTH*) 2) ))

(defparameter *POINTS_PER_SEC* 2000)
(defparameter *MAX_INIT_VEL* 7.0)
(defparameter *MAX_LIFE* 5) ;seconds
(defparameter *MAX_SCALE* 4.0)

(defparameter *WIND_CHANGE* 2.0)
(defparameter *MAX_WIND* 3.0)
(defparameter *SPAWN_INTERVAL* 0.01 )
(defparameter *RUNNING_TIME* (* *MAX_LIFE* 4))
(defparameter *MAX_PTS* (* *RUNNING_TIME* *POINTS_PER_SEC*))

(defparameter *ambient* #(0.8 0.05 0.1 1.0))
(defparameter *diffuse* #(1.0 1.0 1.0 1.0))
;(defparameter *light-pos* #( (+ *MIN_X* (/ (- *MAX_X* *MIN_X*) 2.0) ) *MAX_Y* *MIN_DEPTH* 0.0))
(defparameter *light-pos* #( 0.0 50.0 50.0 0.0))  

(defvar init-t 0.0)
(defvar end-t 0.0)
(defvar gpu-init-t 0.0)
(defvar gpu-end-t 0.0)
(defvar frame-dur 0.0)
(defvar spwn-tmr 0.0)
(defvar cleanup-tmr 0.0)
(defvar run-tmr 0.0)
(defvar frames (make-array (* *RUNNING_TIME* 1000) :initial-element 0.0 :element-type 'single-double) )
(defvar gpu-times (make-array (* *RUNNING_TIME* 1000) :initial-element 0.0 :element-type 'single-double) )
(defvar cur-frame 0)

(defvar windX 0.0) 
(defvar windY 0.0)
(defvar windZ 0.0)
(defvar grav 50)

(defvar max-pt 0)      
(defvar min-pt 0)  
(defvar seed 1234569)

(defstruct Pt (x 0) (y 0) (z 0) (vx 0) (vy 0) (vz 0) (r 0) (life 0) (is nil) )

(defvar pts (make-array *MAX_PTS* :initial-element (make-Pt) :element-type 'Pt) )

(defmethod new-pt ()
  (setf (aref pts max-pt) (make-Pt
                           :x (- (+ 0 (* (random *START_RANGE*))) (/ *START_RANGE* 2) )
                           :y *START_Y*
                           :z (- (+ *START_DEPTH* (* (random *START_RANGE*))) (/ *START_RANGE* 2) )
                           :vx (* (random *MAX_INIT_VEL*))
                           :vy (* (random *MAX_INIT_VEL*))
                           :vz (* (random *MAX_INIT_VEL*))
                           :R (/ (* (random *MAX_SCALE*)) 2)
                           :life (* (random *MAX_LIFE*))
                           :is t
                            )
               )
  (setf max-pt (+ max-pt 1) )
)

(defmethod spwn-pts (secs)
  (let ( (num (round (* secs *POINTS_PER_SEC*)))) 
    (dotimes (i num) (new-pt) ))
)  

(defmethod move-pts (secs)
  (loop for i from min-pt to max-pt when (equal (Pt-is (aref pts i)) t) do (progn
                                      ( setf (pt-x (aref pts i)) (+ (pt-x (aref pts i)) (* (pt-vx (aref pts i)) secs) ) )
                                      ( setf (pt-y (aref pts i)) (+ (pt-y (aref pts i)) (* (pt-vy (aref pts i)) secs) ) )  
                                      ( setf (pt-z (aref pts i)) (+ (pt-z (aref pts i)) (* (pt-vz (aref pts i)) secs) ) )
                                      ( setf (pt-vx (aref pts i)) (+ (pt-vx (aref pts i)) (* (/ 1.0 (pt-R (aref pts i))) windX)))
                                      ( setf (pt-vy (aref pts i)) (+ (pt-vy (aref pts i)) (* (/ 1.0 (pt-R (aref pts i))) windY)))
                                      ( setf (pt-vz (aref pts i)) (+ (pt-vz (aref pts i)) (* (/ 1.0 (pt-R (aref pts i))) windZ)))
                                      ( setf (pt-vy (aref pts i)) (- (pt-vy (aref pts i)) (* grav secs)) )
                                      ( setf (pt-life (aref pts i)) (- (pt-life (aref pts i)) secs) )
                                      ( if (> 0.0 (pt-life (aref pts i)) ) (setf (pt-is (aref pts i)) nil) nil )
                                      ) 
      )
)

(defmethod check-colls ()
  (loop for i from min-pt to max-pt when (equal (Pt-is (aref pts i)) t) do (progn
                                                         (if (< (pt-x (aref pts i)) *MIN_X*) (progn 
                                                                                                     (setf (pt-x (aref pts i)) (+ *MIN_X* (pt-R (aref pts i))) )
                                                                                                     (setf (pt-vx (aref pts i)) (* (pt-vx (aref pts i)) -1.1)) ) nil)
                                                         (if (> (pt-x (aref pts i)) *MAX_X*) (progn 
                                                                                                     (setf (pt-x (aref pts i)) (- *MAX_X* (pt-R (aref pts i))) )
                                                                                                     (setf (pt-vx (aref pts i)) (* (pt-vx (aref pts i)) -1.1)) ) nil)
                                                         (if (< (pt-y (aref pts i)) *MIN_Y*) (progn 
                                                                                                     (setf (pt-y (aref pts i)) (+ *MIN_Y* (pt-R (aref pts i))) )
                                                                                                     (setf (pt-vy (aref pts i)) (* (pt-vy (aref pts i)) -1.1)) ) nil)
                                                         (if (> (pt-y (aref pts i)) *MAX_Y*) (progn 
                                                                                                     (setf (pt-y (aref pts i)) (- *MAX_Y* (pt-R (aref pts i))) )
                                                                                                     (setf (pt-vy (aref pts i)) (* (pt-vy (aref pts i)) -1.1)) ) nil)
                                                         (if (< (pt-z (aref pts i)) *MIN_DEPTH*) (progn 
                                                                                                         (setf (pt-z (aref pts i)) (+ *MIN_DEPTH* (pt-R (aref pts i))) )
                                                                                                         (setf (pt-vz (aref pts i)) (* (pt-vz (aref pts i)) -1.1)) ) nil)
                                                         (if (> (pt-z (aref pts i)) *MAX_DEPTH*) (progn 
                                                                                                         (setf (pt-z (aref pts i)) (- *MAX_DEPTH* (pt-R (aref pts i))) )
                                                                                                         (setf (pt-vz (aref pts i)) (* (pt-vz (aref pts i)) -1.1)) ) nil)
                                                         )
    )
  )

(defmethod do-wind ()
  (setf windX (+ (* (- (* (random *WIND_CHANGE*)) (/ *WIND_CHANGE* 2) ) frame-dur) windX) )
  (setf windY (+ (* (- (* (random *WIND_CHANGE*)) (/ *WIND_CHANGE* 2) ) frame-dur) windY) )
  (setf windZ (+ (* (- (* (random *WIND_CHANGE*)) (/ *WIND_CHANGE* 2) ) frame-dur) windZ) )
  (if (> (abs windX) *MAX_WIND*) (setf windX (* windX -0.5) ) nil)
  (if (> (abs windY) *MAX_WIND*) (setf windY (* windY -0.5) ) nil)
  (if (> (abs windZ) *MAX_WIND*) (setf windZ (* windZ -0.5) ) nil)
 )

(defmethod cleanup-pt-pool ()
  (loop for i from max-pt downto min-pt when (equal (Pt-is (aref pts i)) t) do
    (setf min-pt i)    
   )
)

(defmethod render-pts ()
  (loop for i from min-pt to max-pt when (equal (Pt-is (aref pts i)) t) do (progn
                                      (gl:pop-matrix)
                                      (gl:push-matrix) 
                                      (gl:translate (pt-x (aref pts i)) (pt-y (aref pts i)) (- 0 (pt-z (aref pts i))) ) 
                                      (gl:scale (* (pt-R (aref pts i)) 2) (* (pt-R (aref pts i)) 2) (* (pt-R (aref pts i)) 2))
                                      (gl:draw-arrays :quads 0 24)        
                                      )
      )
 )

(def-window-size-callback window-size-callback (window w h)
  (set-viewport w h))

(defparameter *vertices* (vector -1.0 -1.0 1.0 0.0 0.0 1.0
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

(gl:define-gl-array-format position-normal
  (gl:vertex :type :float :components (x y z))
  (gl:normal :type :float :components (nx ny nz))
)

(defparameter *gVBO* 0)
(defparameter *arr* 0)

(defmethod load-cube-to-gpu ()
  (setf *gVBO* (car (gl:gen-buffers 1)))
  (gl:bind-buffer :array-buffer *gVBO*)
  (setf *arr* (gl:alloc-gl-array :float 144 ) )
  (dotimes (i (length *vertices*))
      (setf (gl:glaref *arr* i) (aref *vertices* i)))
  (gl::buffer-data :array-buffer :static-draw *arr*)

  (gl:enable-client-state :vertex-array)
  (gl:enable-client-state :normal-array)
  (%gl:vertex-pointer 3 :float 24 (cffi:null-pointer) )	
  (%gl:normal-pointer :float 12 (cffi:null-pointer))	
  
  (gl:matrix-mode :modelview)
)

(defun init-scene ()
  (gl::enable :depth-test)
  (gl::enable :lighting)
  (gl:clear-color 0.1 0.1 0.6 1)
  (gl:clear-depth 1)
  (gl:depth-func :lequal)
  (gl:light :light0 :ambient *ambient*) 
  (gl:light :light0 :diffuse *diffuse*) 
  (gl:light :light0 :position *light-pos*) 
  (gl:enable :light0)

  (gl::viewport 0 0 *SCREEN_WIDTH* *SCREEN_HEIGHT*)
  (gl:matrix-mode :projection)
  (gl:load-identity)
  (gl:frustum -1.0 1.0 -1.0 1.0 1.0 1000.0)
  (gl:rotate 20 1.0 0.0 0.0)
  (gl:matrix-mode :modelview)
  (gl:load-identity)
  (gl:push-matrix)
)

(defmethod main-loop ()
  (setf init-t (%glfw:get-time) )
  (move-pts frame-dur)
  (do-wind)
  (if (>= spwn-tmr *SPAWN_INTERVAL*) (progn (spwn-pts *SPAWN_INTERVAL*) (setf spwn-tmr (- spwn-tmr *SPAWN_INTERVAL*)) ) nil)
  (if (>= cleanup-tmr (/ *MAX_LIFE* 1000) ) (progn (cleanup-pt-pool) (setf cleanup-tmr 0.0) ) nil)
  (check-colls)
  (setf gpu-init-t (%glfw:get-time) )
  (gl:clear :color-buffer)
  (gl:clear :depth-buffer)
  (render-pts)
  (swap-buffers)
  (poll-events)
  (setf gpu-end-t (%glfw:get-time) )
  (setf end-t (%glfw:get-time) )
  (setf frame-dur (- end-t init-t) )
  (setf spwn-tmr (+ spwn-tmr frame-dur) )
  (setf cleanup-tmr (+ cleanup-tmr frame-dur) )
  (setf run-tmr (+ run-tmr frame-dur) )
  (if (>= run-tmr (/ *MAX_LIFE* 1000) ) (progn 
                                          (setf (aref frames cur-frame) frame-dur) 
                                          (setf cur-frame (round (+ cur-frame 1.0)) )
                                          (setf (aref gpu-times cur-frame) (- gpu-end-t gpu-init-t)) nil ))
  (if (< run-tmr *RUNNING_TIME*) (main-loop)
      (let ((framerate-sum 0.0) (gputime-sum 0.0)) (progn 
                       (loop for i from 0 to cur-frame do (setf framerate-sum (+ framerate-sum (aref frames i) ) ) )
                       (format t "Average framerate was: ~f frames per second.~%" (/ 1.0 (/ framerate-sum cur-frame)) )
                       (loop for i from 0 to cur-frame do (setf gputime-sum (+ gputime-sum (aref gpu-times i) ) ) )
                       (format t "Average cpu time was- ~f seconds per frame.~%" (- (/ framerate-sum cur-frame) (/ gputime-sum cur-frame) ) )
                       (if (equal *PRINT_FRAMES* t) (progn 
                                                            (princ "--:") 
                                                            (loop for i from 0 to (- cur-frame 1) do (progn (format t "~f," (/ 1.0 (aref frames i)) )  ) )
                                                            (princ ".--")
                                                       ) nil ) )
        )
      )
)

(defun run ()
  (with-init-window (:title *TITLE* :width *SCREEN_WIDTH* :height *SCREEN_HEIGHT* :context-version-major 2 :context-version-minor 1)
    (set-key-callback 'key-callback)
    (set-window-size-callback 'window-size-callback)
    (load-cube-to-gpu)    
    (loop until (window-should-close-p)
       do (init-scene)
       do (set-window-should-close)
       do (main-loop)
    )
  )
)
