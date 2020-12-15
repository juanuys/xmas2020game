package ent;
import Data.ObjectKind;

class Object extends Entity {

	var speed = 0.2;
	var angle = 0.;
	var wasCarried = false;
	var color : h3d.shader.ColorAdd;
	var pulse : Float = 0.;
	var hintAct : h2d.Anim;
	public var active : Bool;
	public var carried(default, set) : Bool = false;

	public function new(k, x, y) {
		super(k, x, y);
		switch( kind ) {
		case Square1, Square2, Square3, Wings:
			var a = new h2d.Anim([for( i in 0...9 ) game.tiles.sub(i * 32, 256 + (kind == Wings ? 64 : kind == Square2 ? 32 : 0), 32, 32, -16, -16)], 20, spr);
			a.loop = false;
			a.onAnimEnd = function() {
				haxe.Timer.delay(function() {
					a.currentFrame = 0;
				}, 200 + Std.random(400));
			};
			if( kind == Square3 )
				a.adjustColor({ hue : Math.PI / 2 });
			hintAct = a;
		case Plate1, Plate2, Plate3, Plate4:
			game.soilLayer.add(Std.int(x) * 32, Std.int(y) * 32, game.tiles.sub(64, 32, 32, 32));
			spr.alpha = 0.8;
		default:
		}
	}

	function set_carried(b) {
		var ix = Std.int(x);
		var iy = Std.int(y);
		if( b )
			active = false;
		wasCarried = carried;
		game.world.add(spr, b ? Game.LAYER_CARRY : Game.LAYER_ENT);
		if( b )
			angle = Math.atan2(game.hero.y - y, game.hero.x - x);
		return carried = b;
	}

	override function isCollide( with : ent.Entity ) {
		return with != null && with.kind != Hero;
	}

	override function canPick() {
		if( hasFlag(Under) )
			return false;
		if( carried )
			return false;
		return true;
	}

	override function getAnim() {
		return switch( kind ) {
		case Exit:
			[for( i in 0...6 ) game.tiles.sub(i * 32, 160, 32, 32, -16, -16)];
		default:
			super.getAnim();
		}
	}

	override public function update(dt:Float) {

		if( hintAct != null )
			hintAct.visible = !active;
		else if( active ) {
			pulse += dt * 0.1;
			spr.adjustColor({ saturation : Math.abs(Math.sin(pulse)) * 0.5, lightness : Math.abs(Math.sin(pulse)) * 0.2 });
		} else if( pulse != 0 ) {
			pulse %= Math.PI;
			pulse += dt * 0.1;
			if( pulse > Math.PI )
				pulse = 0;
			spr.adjustColor({ saturation : Math.abs(Math.sin(pulse)) * 0.5, lightness : Math.abs(Math.sin(pulse)) * 0.2 });
		}


		if( carried ) {
			var hero = game.hero;
			var index = hero.carry.length - 1 - hero.carry.indexOf(this);
			var hpos = hero.history[hero.history.length - 2 - index * 3];
			if( hpos == null ) hpos = hero.history[hero.history.length - 1];
			var step = ent.Hero.STEP;
			if( hpos == null ) hpos = { x : Std.int(hero.x * step), y : Std.int(hero.y * step) };
			var tx = (hpos.x / step) * 32;
			var ty = (hpos.y / step) * 32;
			var tangle = Math.atan2(ty - spr.y, tx - spr.x);

			if( spr.scaleX > 0.5 ) {
				spr.smooth = true;
				spr.scale(Math.pow(0.95, dt));
				if( spr.scaleX < 0.5 )
					spr.setScale(0.5);
			}

			angle = hxd.Math.angleMove(angle, tangle, 0.4 * dt);
			var ds = speed * dt * hxd.Math.distance(spr.x - tx, spr.y - ty);
			spr.x += Math.cos(angle) * ds;
			spr.y += Math.sin(angle) * ds;
			return;
		} else {
			switch( kind ) {
			case Plate1, Plate2, Plate3, Plate4:
				active = getObj(Std.int(x), Std.int(y)) != null;
			default:
			}
		}

		if( spr.scaleX < 1 ) {
			spr.scale(Math.pow(1.05, dt));
			if( spr.scaleX > 1 ) {
				spr.setScale(1);
				spr.smooth = false;
			}
		}

		var ix = Std.int(x), iy = Std.int(y);
		switch( kind ) {
		case Exit:
			if( game.allActive ) {
				spr.speed = 15;
			} else {
				spr.speed = 0;
				spr.currentFrame = 0;
			}
		case Square1:
			active = getObj(ix, iy, [Plate1, Plate2][game.hueValue], [CanPutOver]) != null;
		case Square2:
			active = getObj(ix, iy, [Plate2, Plate1][game.hueValue], [CanPutOver]) != null;
		case Square3:
			if( game.hueValue == 0 )
				active = getObj(ix, iy, Plate3, [CanPutOver]) != null || getObj(ix, iy, Steal, [CanPutOver]) != null;
			else
				active = getObj(ix, iy, Plate4, [CanPutOver]) != null;
		case Wings:
			var obj = getObj(ix, iy, [CanPutOver]);
			active = obj != null && obj.kind != Steal;
		default:
		}

		if( wasCarried ) {
			var tx = x * 32, ty = y * 32;
			var d = hxd.Math.distance(tx - spr.x, ty - spr.y);
			if( d > 1 ) {
				spr.x = hxd.Math.lerp(spr.x, tx, 1 - Math.pow(0.7, dt));
				spr.y = hxd.Math.lerp(spr.y, ty, 1 - Math.pow(0.7, dt));
				return;
			}
			wasCarried = false;
		}

		super.update(dt);

	}

}