(defproject cjpb "0.1.0-SNAPSHOT"
  :description "Clojure implementation of an OpenGL particle animation benchmark"
  :url "https://github.com/logicchains/ParticleBench"
  :license {:name "Eclipse Public License"
            :url "http://www.eclipse.org/legal/epl-v10.html"}
  :java-source-paths ["lib"] 
  :jvm-opts ["-Djava.library.path=native/linux"]
  :dependencies [[org.clojure/clojure "1.5.1"]
                [org.clojure/math.numeric-tower "0.0.3"]
                [org.lwjgl/lwjgl "2.7.1"]
                [org.lwjgl/lwjgl-util "2.7.1"]]
  :main ^:skip-aot cjpb.core
  :target-path "target/%s"
  :profiles {:uberjar {:aot :all}})
