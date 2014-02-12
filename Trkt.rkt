#lang typed/racket
(require/typed ffi/unsafe
               [#:opaque CPointer cpointer?])
(require/typed ffi/vector 
               [#:opaque F32vector f32vector?]
               [#:opaque U32vector u32vector?]
               [f32vector (Float * -> F32vector)]
               [u32vector-ref (U32vector Integer -> Integer)])
(require/typed RacketGL/opengl/main
               [GL_QUADS Index]
               [GL_ARRAY_BUFFER Index]
               [GL_STATIC_DRAW Index]
               [GL_VERTEX_ARRAY Index]
               [GL_NORMAL_ARRAY Index]
               [GL_MODELVIEW Index]
               [GL_PROJECTION Index]
               [GL_FLOAT Index]
               [GL_DEPTH_TEST Index]
               [GL_LIGHTING Index]
               [GL_LEQUAL Index]
               [GL_LIGHT0 Index]
               [GL_AMBIENT Index]
               [GL_DIFFUSE Index]
               [GL_POSITION Index]
               [GL_COLOR_BUFFER_BIT Index]
               [GL_DEPTH_BUFFER_BIT Index]
               [glClear (Index -> Any)]
               [glPopMatrix (-> Any)]
               [glPushMatrix (-> Any)]
               [glLoadIdentity (-> Any)]
               [glTranslatef (Float Float Float -> Any)]
               [glScalef (Float Float Float -> Any)]
               [glDrawArrays (Index Integer Integer -> Any)]
               [glBindBuffer (Index Integer -> Any)]
               [glBufferData (Index Integer F32vector Index -> Any)]
               [glEnableClientState (Index -> Any)]
               [glDisableClientState (Index -> Any)]
               [glVertexPointer (Integer Index Integer Integer -> Any)]
               [glNormalPointer (Index Integer Integer -> Any)]
               [glMatrixMode (Index -> Any)]
               [glRotatef (Float Float Float Float -> Any)]
               [glGenBuffers (Integer -> U32vector)]
               [glEnable (Index -> Any)]
               [glClearColor (Float Float Float Float -> Any)]
               [glClearDepth (Float -> Any)]
               [glDepthFunc (Index -> Any)]
               [glLightfv (Index Index F32vector -> Any)]
               [glViewport (Integer Integer Integer Integer -> Any)]               
               [glFrustum (Float Float Float Float Float Float -> Any)]
               [gl-vector-sizeof (F32vector -> Integer)])
(require/typed sdl/sdl/main 
               [SDL_INIT_VIDEO Index]
               [SDL_WINDOWPOS_UNDEFINED Index]
               [SDL_RenderPresent (CPointer -> Any)]
               [SDL_Init (Index -> Any)]
               [SDL_CreateWindow (String Index Index Index Index Byte -> CPointer)]
               [SDL_CreateRenderer (CPointer Integer Integer -> CPointer)]
               [SDL_GetWindowSurface (CPointer -> CPointer)]
               [SDL_GetError (-> String)]
               [SDL_GL_SwapWindow (CPointer -> Any)]
               [SDL_GL_CreateContext (CPointer -> CPointer)]
               [SDL_GL_MakeCurrent (CPointer CPointer -> Any)]
               [SDL_DestroyWindow (CPointer -> Any)]
               [SDL_GL_DeleteContext (CPointer -> Any)]
               [SDL_Quit (-> Any)])
(require racket/performance-hint)

(define *PRINT_FRAMES* #t)
(define *SCREEN_WIDTH* 800)
(define *SCREEN_HEIGHT* 600)
(define *TITLE* "ParticleBench")

(define *MIN_X* -80.0)
(define *MAX_X* 80.0)
(define *MIN_Y* -90.0)
(define *MAX_Y* 50.0)
(define *MIN_DEPTH* 50.0)
(define *MAX_DEPTH* 250.0)

(define *START_RANGE* 15.0)
(define *START_X* (+ *MIN_X* (/ (+ *MIN_X* *MAX_X*) 2) ) )
(define *START_Y* *MAX_Y*)
(define *START_DEPTH* (+ *MIN_DEPTH* (/ (+ *MIN_DEPTH* *MAX_DEPTH*) 2) ))

(define *POINTS_PER_SEC* 2000)
(define *MAX_INIT_VEL* 7.0)
(define *MAX_LIFE* 5) ;seconds
(define *MAX_SCALE* 4.0)

(define *WIND_CHANGE* 2.0)
(define *MAX_WIND* 3.0)
(define *SPAWN_INTERVAL* 0.01 )
(define *RUNNING_TIME* (* *MAX_LIFE* 4))
(define *MAX_PTS* (* *RUNNING_TIME* *POINTS_PER_SEC*))

(define: init-t : Float 0.0)
(define: end-t : Float  0.0)
(define: gpu-init-t : Float  0.0)
(define: gpu-end-t : Float  0.0)
(define: frame-dur : Float  0.0)
(define: spwn-tmr : Float  0.0)
(define: cleanup-tmr : Float  0.0)
(define: run-tmr : Float  0.0)
(define frames (make-vector (* *RUNNING_TIME* 1000) 0.0)  )
(define gpu-times (make-vector (* *RUNNING_TIME* 1000) 0.0)  )
(define: cur-frame : Integer 0)

(define: windX : Float  0.0) 
(define: windY : Float  0.0)
(define: windZ : Float  0.0)
(define: grav : Float  50.0)

;(define sdl-window 0)
;(define sdl-renderer 0)
;(define gl-context 0)
;(define screen-surface 0)

(define vbo 0)
(define ambient (f32vector 0.8 0.05 0.1 1.0))
(define diffuse (f32vector 1.0 1.0 1.0 1.0))
(define light-pos (f32vector (+ *MIN_X* (/ (- *MAX_X* *MIN_X*) 2) ) *MAX_Y* *MIN_DEPTH* 0.0))

(struct: pt ([x : Float] [y : Float] [z : Float] [vx : Float] [vy : Float]
                         [vz : Float] [R : Float] [life : Float] [is : Boolean])
  #:mutable) 

(define: max-pt : Integer 0)      
(define: min-pt : Integer 0)  
(define seed 1234569)

(define pts (make-vector *MAX_PTS* [pt 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 #f])) 

(define vertex-normal-array
  (f32vector
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

(define (new-pt dummy)
;  (let ([apt (vector-ref pts max-pt)]) (begin
;                                      ( set-pt-x! apt (- (+ 0.0 (* (random) *START_RANGE*)) (/ *START_RANGE* 2) ) )
;                                      ( set-pt-y! apt *START_Y* )
;                                      ( set-pt-z! apt (- (+ *START_DEPTH* (* (random) *START_RANGE*)) (/ *START_RANGE* 2) ) )
;                                      ( set-pt-vx! apt (* (random) *MAX_INIT_VEL*))
;                                     ( set-pt-vy! apt (* (random) *MAX_INIT_VEL*))
;                                      ( set-pt-vz! apt (* (random) *MAX_INIT_VEL*))
;                                      ( set-pt-R! apt (/ (* (random) *MAX_SCALE* ) 2.0))
;                                      ( set-pt-life! apt (* (random) *MAX_LIFE*) )
;                                      ( set-pt-is! apt #t)))
  (vector-set! pts max-pt ( pt
                            (- (+ 0.0 (* (random) *START_RANGE*)) (/ *START_RANGE* 2) )
                            *START_Y*
                            (- (+ *START_DEPTH* (* (random) *START_RANGE*)) (/ *START_RANGE* 2) )
                            (* (random) *MAX_INIT_VEL*)
                            (* (random) *MAX_INIT_VEL*)
                            (* (random) *MAX_INIT_VEL*)
                            (/ (* (random) *MAX_SCALE* ) 2.0)
                            (* (random) *MAX_LIFE*)
                            #t))
  (set! max-pt (+ max-pt 1)))

(: spwn-pts (Float -> Any))
(define (spwn-pts secs)
  (let ([num (* secs *POINTS_PER_SEC*)])
    (for ([i (in-range 0 num )]) (new-pt "dummy") )))

(: move-pts (Float -> Any))
(define (move-pts secs)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (pt-is (vector-ref pts i)) #t) )
    (let ([apt (vector-ref pts i)]) (begin
                                      ( set-pt-x! apt (+ (pt-x apt) (* (pt-vx apt) secs) ) )
                                      ( set-pt-y! apt (+ (pt-y apt) (* (pt-vy apt) secs) ) )
                                      ( set-pt-z! apt (+ (pt-z apt) (* (pt-vz apt) secs) ) )
                                      ( set-pt-vx! apt (+ (pt-vx apt) (/ windX (pt-R apt)) ))
                                      ( set-pt-vy! apt (+ (pt-vy apt) (/ windY (pt-R apt))))
                                      ( set-pt-vz! apt (+ (pt-vz apt) (/ windZ (pt-R apt))))
                                      ( set-pt-vy! apt (- (pt-vy apt) (* grav secs)) )
                                      ( set-pt-life! apt (- (pt-life apt) secs) )
                                      ( if (> 0.0 (pt-life apt) ) (set-pt-is! apt #f) #f )))))

(define (check-colls)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (pt-is (vector-ref pts i)) #t) ) (begin        
                                                         (if (< (pt-x (vector-ref pts i)) *MIN_X*) (begin 
                                                                                                     (set-pt-x! (vector-ref pts i) (+ *MIN_X* (pt-R (vector-ref pts i))) )
                                                                                                     (set-pt-vx! (vector-ref pts i) (* (pt-vx (vector-ref pts i)) -1.1)) ) #f)
                                                         (if (> (pt-x (vector-ref pts i)) *MAX_X*) (begin 
                                                                                                     (set-pt-x! (vector-ref pts i) (- *MAX_X* (pt-R (vector-ref pts i))) )
                                                                                                     (set-pt-vx! (vector-ref pts i) (* (pt-vx (vector-ref pts i)) -1.1)) ) #f)
                                                         (if (< (pt-y (vector-ref pts i)) *MIN_Y*) (begin 
                                                                                                     (set-pt-y! (vector-ref pts i) (+ *MIN_Y* (pt-R (vector-ref pts i))) )
                                                                                                     (set-pt-vy! (vector-ref pts i) (* (pt-vy (vector-ref pts i)) -1.1)) ) #f)
                                                         (if (> (pt-y (vector-ref pts i)) *MAX_Y*) (begin 
                                                                                                     (set-pt-y! (vector-ref pts i) (- *MAX_Y* (pt-R (vector-ref pts i))) )
                                                                                                     (set-pt-vy! (vector-ref pts i) (* (pt-vy (vector-ref pts i)) -1.1)) ) #f)
                                                         (if (< (pt-z (vector-ref pts i)) *MIN_DEPTH*) (begin 
                                                                                                         (set-pt-z! (vector-ref pts i) (+ *MIN_DEPTH* (pt-R (vector-ref pts i))) )
                                                                                                         (set-pt-vz! (vector-ref pts i) (* (pt-vz (vector-ref pts i)) -1.1)) ) #f)
                                                         (if (> (pt-z (vector-ref pts i)) *MAX_DEPTH*) (begin 
                                                                                                         (set-pt-z! (vector-ref pts i) (- *MAX_DEPTH* (pt-R (vector-ref pts i))) )
                                                                                                         (set-pt-vz! (vector-ref pts i) (* (pt-vz (vector-ref pts i)) -1.1)) ) #f))))

(define (do-wind)
  (set! windX (+ (* (- (* (random) *WIND_CHANGE*) (/ *WIND_CHANGE* 2) ) frame-dur) windX) )
  (set! windY (+ (* (- (* (random) *WIND_CHANGE*) (/ *WIND_CHANGE* 2) ) frame-dur) windY) )
  (set! windZ (+ (* (- (* (random) *WIND_CHANGE*) (/ *WIND_CHANGE* 2) ) frame-dur) windZ) )
  (if (> (abs windX) *MAX_WIND*) (set! windX (* windX -0.5) ) #f)
  (if (> (abs windY) *MAX_WIND*) (set! windY (* windY -0.5) ) #f)
  (if (> (abs windZ) *MAX_WIND*) (set! windZ (* windZ -0.5) ) #f))

(: render-pts (CPointer -> Any))
(define (render-pts sdl-renderer)
  (for ([i (in-range min-pt max-pt)]
        #:when (equal? (pt-is (vector-ref pts i)) #t) )
    (let ([apt (vector-ref pts i)]) (begin 
                                      (glPopMatrix)
                                      (glPushMatrix) 
                                      (glTranslatef (pt-x apt) (pt-y apt) (- 0.0 (pt-z apt)) ) 
                                      (glScalef (* (pt-R apt) 2.0) (* (pt-R apt) 2.0) (* (pt-R apt) 2.0))
                                      (glDrawArrays GL_QUADS 0 24))))
  (SDL_RenderPresent sdl-renderer))

(define (cleanup-pt-pool)
  (for ([i (in-range min-pt max-pt)])
      ;  #:final (equal? (pt-is (vector-ref pts i)) #t) )
    (if (equal? (pt-is (vector-ref pts i)) 1) (set! min-pt i) #f)))

(define (load-cube-to-gpu)
  (set! vbo (u32vector-ref (glGenBuffers 1) 0))
  (glBindBuffer GL_ARRAY_BUFFER vbo)
  (glBufferData GL_ARRAY_BUFFER
                (gl-vector-sizeof vertex-normal-array)
                vertex-normal-array
                GL_STATIC_DRAW)  
  (glEnableClientState GL_VERTEX_ARRAY)
  (glEnableClientState GL_NORMAL_ARRAY)
  (glVertexPointer 3 GL_FLOAT 24 0)
  (glNormalPointer GL_FLOAT 24 12)
  (glMatrixMode GL_MODELVIEW))

(struct: gpu-state ([sdl-window : CPointer] [sdl-renderer : CPointer] [screen-surface : CPointer] [gl-context : CPointer]))   

(: init (-> gpu-state))
(define (init) 
  (random-seed seed)
  (SDL_Init SDL_INIT_VIDEO)
  (define sdl-window (SDL_CreateWindow *TITLE* SDL_WINDOWPOS_UNDEFINED SDL_WINDOWPOS_UNDEFINED *SCREEN_WIDTH* *SCREEN_HEIGHT* #x00000002))
  (define sdl-renderer (SDL_CreateRenderer sdl-window -1 0))
 ; (if (sdl-window)
  ;    (begin
        (define screen-surface (SDL_GetWindowSurface sdl-window))
        (define gl-context (SDL_GL_CreateContext sdl-window))
        (SDL_GL_MakeCurrent sdl-window gl-context)  
;      (printf "Window could not be created! SDL_Error: ~a\n" (SDL_GetError)))
  (gpu-state sdl-window sdl-renderer screen-surface gl-context))
  
(define (init-gl)
  (glEnable GL_DEPTH_TEST)
  (glEnable GL_LIGHTING)
  (glClearColor 0.1 0.1 0.6 1.0)
  (glClearDepth 1.0)
  (glDepthFunc GL_LEQUAL)
  
  (glLightfv GL_LIGHT0 GL_AMBIENT ambient)
  (glLightfv GL_LIGHT0 GL_DIFFUSE diffuse)
  (glLightfv GL_LIGHT0 GL_POSITION light-pos)
  (glEnable GL_LIGHT0)
  
  (glViewport 0 0 *SCREEN_WIDTH* *SCREEN_HEIGHT*)
  (glMatrixMode GL_PROJECTION)
  (glLoadIdentity)
  (glFrustum -1.0 1.0 -1.0 1.0 1.0 1000.0)
  (glRotatef 20.0 1.0 0.0 0.0)
  (glMatrixMode GL_MODELVIEW)
  (glLoadIdentity)
  (glPushMatrix))

(: close (gpu-state -> Any))
(define (close a-gpu-state) 
  (glDisableClientState GL_VERTEX_ARRAY)
  (glDisableClientState GL_NORMAL_ARRAY)
  (SDL_GL_DeleteContext (gpu-state-gl-context a-gpu-state))
  (SDL_DestroyWindow (gpu-state-sdl-window a-gpu-state))
  (SDL_Quit))

(define (cur-time) (/ (cast (current-inexact-milliseconds) Float) 1000.0))

(: main-loop (gpu-state -> Any))
(define (main-loop a-gpu-state)
  (set! init-t (cur-time) )
  (move-pts frame-dur)
  (do-wind)
  (if (>= spwn-tmr *SPAWN_INTERVAL*) (begin (spwn-pts *SPAWN_INTERVAL*) (set! spwn-tmr (- spwn-tmr *SPAWN_INTERVAL*)) ) #f)
;  (if (>= cleanup-tmr (/ *MAX_LIFE* 1000) ) (begin (cleanup-pt-pool) (set! cleanup-tmr 0.0) ) #f)
  (check-colls)
  (set! gpu-init-t (cur-time) )
  (glClear GL_COLOR_BUFFER_BIT)
  (glClear GL_DEPTH_BUFFER_BIT)
  (render-pts (gpu-state-sdl-renderer a-gpu-state))
  (SDL_GL_SwapWindow (gpu-state-sdl-window a-gpu-state))
  (set! gpu-end-t (cur-time) )
  (set! end-t (cur-time) )
  (set! frame-dur (- end-t init-t) )
  (set! spwn-tmr (+ spwn-tmr frame-dur) )
  (set! cleanup-tmr (+ cleanup-tmr frame-dur) )
  (set! run-tmr (+ run-tmr frame-dur) )
  (if (>= run-tmr (quotient *MAX_LIFE* 1000) ) (begin 
                                          ( vector-set! frames cur-frame frame-dur)
                                          ( vector-set! gpu-times cur-frame (- gpu-end-t gpu-init-t))  
                                          ( set! cur-frame (+ cur-frame 1) ) ) #f )
  (if (< run-tmr *RUNNING_TIME*) (main-loop a-gpu-state)
      (let ([framerate-sum 0.0] [gputime-sum 0.0]) (begin 
                       (for ([i (in-range 0 cur-frame)]) (set! framerate-sum (+ framerate-sum (vector-ref frames i) ) ) )
                       (for ([i (in-range 0 cur-frame)]) (set! gputime-sum (+ gputime-sum (vector-ref gpu-times i) ) ) )
                       (display "Average framerate was: ") (display (/ 1 (/ framerate-sum cur-frame) ) ) (display " frames per second.\n") )
                       (display "Average cpu time was- ") (display (- (/ framerate-sum cur-frame) (/ gputime-sum cur-frame) )) (display " seconds per frame.\n" )
                       (if (equal? *PRINT_FRAMES* #t) (begin 
                                                            (display "--:") 
                                                            (for ([i (in-range 0 (- cur-frame 1))]) (begin (display (/ (vector-ref frames i)) ) (display ",") ) )
                                                            (display ".--")
                                                       ) #f ))))

(define a-gpu-state (init))
(init-gl)
(load-cube-to-gpu)
(main-loop a-gpu-state)
(close a-gpu-state)
